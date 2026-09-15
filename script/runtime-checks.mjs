import { printTable } from './table.mjs';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const aliases = { quick: 'quickswap', pancake: 'pancakeswap', spooky: 'spookyswap', spark: 'sparkdex', dragon: 'dragonswap', externalapi: 'external' };
const normalize = value => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const integrationKey = value => aliases[normalize(value)] ?? normalize(value);
const lower = value => String(value ?? '').toLowerCase();
const sameAddress = (a, b) => /^0x[0-9a-f]{40}$/.test(lower(a)) && lower(a) === lower(b);
const fresh = (value, now, age = 120_000) => {
  const time = typeof value === 'number' ? value : Date.parse(value);
  return Number.isFinite(time) && now - time >= -30_000 && now - time <= age;
};
export function evaluate({ config, skill, records, relayHealth, relayStatus, takers, now = Date.now() }) {
  const failures = [];
  const checkTakers = takers !== undefined;
  const runtime = new Map(records.filter(r => r[0] === 'runtime').map(r => [r[2], r]));
  const idsByLabel = new Map([...runtime].map(([id, row]) => [row[1], id]));
  const rpcErrors = records.filter(r => r[0] === 'issue' && /rpc-error|RPC failure|chain context failed/.test(r[3]));
  const deployed = new Map(records.filter(r => r[0] === 'dex').map(r => [`${idsByLabel.get(r[1])}:${integrationKey(r[2])}`, r[5] === '-']));
  const chainNames = new Map([...skill.matchAll(/^\d+\. (.+) - `(\d+)`/gm)].map(([, name, id]) => [id, name]));
  const relayAvailable = relayHealth && relayStatus && Array.isArray(relayStatus.chains) && Array.isArray(relayStatus.blockFetchStatus);
  const relayHealthy = relayAvailable && relayHealth.status === 'healthy' && relayStatus.service === 'order-sink'
    && fresh(relayHealth.timestamp, now) && fresh(relayStatus.timestamp, now);
  if (!relayHealthy) failures.push('Relay: unavailable, unhealthy, stale, or invalid health/status response');
  const polled = new Set((relayStatus?.takerFetchStats ?? []).filter(s => s.requestCount > 0 && fresh(s.lastFetchAt, now)).map(s => s.serverId));
  const activeTakers = (takers ?? []).filter(t => t.takerType === 'safo_taker' && t.failoverActive === true
    && fresh(t.Timestamp, now) && polled.has(t.nodeAddress));
  if (checkTakers && !activeTakers.length) failures.push('Takers: no fresh active SAFO taker with recent relay polling');

  const dependencyRows = [];
  for (const [id, chainConfig] of Object.entries(config)) {
    if (id === '*') continue;
    const live = runtime.get(id);
    const chain = chainNames.get(id) ?? id;
    const chainErrors = rpcErrors.filter(r => idsByLabel.get(r[1]) === id);
    const contractsUnknown = chainErrors.some(r => !r[2].startsWith('oracle'));
    const relayChain = relayStatus?.chains?.find(c => String(c.chainId) === id);
    const listener = relayStatus?.blockFetchStatus?.find(c => String(c.chainId) === id);
    const listenerReady = relayHealthy && relayChain && listener?.eventsFetchingEnabled === true
      && listener.listenerActive === true && listener.lastBlock > 0 && fresh(listener.updatedAt, now);
    if (live && !listenerReady) failures.push(`${chain}: relay listener missing, disabled, or stale`);
    const networks = activeTakers.flatMap(t => Object.entries(t.metadata?.networks ?? {})
      .filter(([, n]) => String(n.id) === id).map(([name, metadata]) => ({ metadata, running: t.networks?.[name] })));
    const expectedSolvers = { ...config['*']?.adapter, ...chainConfig.adapter };
    const refinery = chainConfig.refinery ?? config['*']?.refinery;
    const readyNetworks = networks.filter(n => sameAddress(n.metadata.addresses?.refinery, refinery)
      && Object.entries(expectedSolvers).every(([solver, address]) => sameAddress(n.metadata.addresses?.spot?.routerAdapters?.[solver], address)));
    if (checkTakers && live && !readyNetworks.length) {
      failures.push(`${chain}: taker network/refinery/solver adapters unavailable or mismatched (${Object.keys(expectedSolvers).join(',') || 'shared'})`);
    }
    const dexes = Object.entries({ ...config['*']?.dex, ...chainConfig.dex });
    const chainChecks = [];
    for (const [key, dex] of dexes) {
      const name = integrationKey(key);
      const contracts = live && !contractsUnknown ? live[3] === 'supported' && deployed.get(`${id}:${name}`) === true : null;
      const relay = !live || !relayAvailable ? null : Boolean(listenerReady
        && relayChain.exchanges?.some(e => sameAddress(e.address, dex.adapter)));
      const taker = !live || !takers || !relayStatus ? null : readyNetworks.some(n => Object.entries(n.running?.dexes ?? {})
        .some(([key, metrics]) => integrationKey(key) === name && fresh(metrics.lastOnBlocksExecution, now, 180_000)
          && (metrics.lastScannedBlockAge ?? 0) <= 120_000 && Object.keys(metrics.errors ?? {}).length === 0));
      if (contracts && relay !== true) failures.push(`${chain}/${key}: relay adapter unregistered or listener unavailable`);
      if (checkTakers && contracts && taker !== true) failures.push(`${chain}/${key}: taker loop missing, stale, unhealthy, or metadata mismatched`);
      chainChecks.push({ contracts, takers: taker, relay });
    }
    if (live) {
      const active = chainChecks.filter(c => c.contracts);
      dependencyRows.push([chain, `${active.length}/${dexes.length}`, live[6],
        !checkTakers ? 'skipped' : takers && relayStatus ? `${active.filter(c => c.takers).length}/${active.length}` : 'unknown',
        relayAvailable ? `${active.filter(c => c.relay).length}/${active.length}` : 'unknown']);
    }
  }

  return { dependencyRows, failures };
}

async function main() {
  const records = readFileSync(0, 'utf8').trim().split('\n').filter(Boolean).map(line => line.split('\t'));
  const skill = readFileSync(resolve(root, 'skill/SKILL.md'), 'utf8');
  const relay = skill.match(/https:\/\/[^\s`]+(?=\/orders\/new)/)?.[0];
  if (!relay) throw new Error('Relay endpoint missing from skill');
  const urls = (process.env.SPOT_TAKER_HEALTH_URLS ?? '').split(',').map(s => s.trim()).filter(Boolean);
  const getJson = async url => {
    const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  };
  const sources = await Promise.allSettled([getJson(`${relay}/health`), getJson(`${relay}/status`),
    urls.length ? Promise.all(urls.map(getJson)) : undefined]);
  const values = sources.map(result => result.status === 'fulfilled' ? result.value : null);
  const result = evaluate({ config: JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf8')), skill, records,
    relayHealth: values[0], relayStatus: values[1], takers: values[2] });
  sources.forEach((source, i) => {
    if (source.status === 'rejected') result.failures.push(`${['Relay health', 'Relay status', 'Taker health'][i]}: request failed (${source.reason.name})`);
  });
  console.log('\n🔎 Live runtime coverage (active integrations; taker polling/loops; relay registration/listeners)');
  if (!urls.length) console.log('⏭️ Taker health checks skipped: SPOT_TAKER_HEALTH_URLS is not configured.');
  printTable(['chain', 'Spot active/configured', 'Oracle', 'Takers', 'Relay'], result.dependencyRows);
  if (result.failures.length) {
    console.log('\n❌ Runtime failures');
    printTable(['detail'], result.failures.map(detail => [detail]));
    process.exitCode = 1;
  } else console.log('✅ Runtime dependencies match.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('❌ Runtime check failed: invalid input or unavailable dependency'); process.exitCode = 1; });
}
