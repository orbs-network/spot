import { printTable } from './table.mjs';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const database = '***REMOVED***';
const columns = { contracts: 'Contracts', oracle: 'Oracle', takers: '***REMOVED***', relay: '***REMOVED***' };
const aliases = { quick: 'quickswap', pancake: 'pancakeswap', spooky: 'spookyswap', spark: 'sparkdex', dragon: 'dragonswap', externalapi: 'external' };
const normalize = value => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const integrationKey = value => aliases[normalize(value)] ?? normalize(value);
const lower = value => String(value ?? '').toLowerCase();
const sameAddress = (a, b) => /^0x[0-9a-f]{40}$/.test(lower(a)) && lower(a) === lower(b);
const fresh = (value, now, age = 120_000) => {
  const time = typeof value === 'number' ? value : Date.parse(value);
  return Number.isFinite(time) && now - time >= -30_000 && now - time <= age;
};
const progress = flags => flags.includes(null) ? null : flags.every(Boolean) ? 'Done' : flags.some(Boolean) ? 'In progress' : 'Not started';

export async function readNotion(fetcher, token) {
  if (!token) throw new Error('NOTION_API_KEY is required');
  const pages = [];
  const cursors = new Set();
  let cursor;
  do {
    const response = await fetcher(`https://api.notion.com/v1/databases/${database}/query`, {
      method: 'POST', signal: AbortSignal.timeout(20_000),
      headers: { Authorization: `Bearer ${token}`, 'Notion-Version': '2022-06-28', 'Content-Type': 'application/json' },
      body: JSON.stringify({ page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) }),
    });
    if (!response.ok) throw new Error(`Notion HTTP ${response.status}`);
    const data = await response.json();
    if (!Array.isArray(data.results)) throw new Error('Invalid Notion query response');
    pages.push(...data.results);
    if (!data.has_more) break;
    cursor = data.next_cursor;
    if (!cursor || cursors.has(cursor)) throw new Error('Invalid Notion pagination cursor');
    cursors.add(cursor);
  } while (true);
  return pages;
}

export function evaluate({ config, skill, records, relayHealth, relayStatus, takers, notionPages, now = Date.now() }) {
  const failures = [];
  const warnings = [];
  const runtime = new Map(records.filter(r => r[0] === 'runtime').map(r => [r[2], r]));
  const idsByLabel = new Map([...runtime].map(([id, row]) => [row[1], id]));
  const rpcErrors = records.filter(r => r[0] === 'issue' && /rpc-error|RPC failure|chain context failed/.test(r[3]));
  const deployed = new Map(records.filter(r => r[0] === 'dex').map(r => [`${idsByLabel.get(r[1])}:${integrationKey(r[2])}`, r[5] === '-']));
  const chainNames = new Map([...skill.matchAll(/^\d+\. (.+) - `(\d+)`/gm)].map(([, name, id]) => [id, name]));
  const chainIds = new Map([...chainNames].map(([id, name]) => [normalize(name), id]));
  for (const [alias, name] of Object.entries({ avax: 'Avalanche', bnb: 'BNB Chain', arbitrum: 'Arbitrum One' })) {
    if (chainIds.has(normalize(name))) chainIds.set(alias, chainIds.get(normalize(name)));
  }
  const relayAvailable = relayHealth && relayStatus && Array.isArray(relayStatus.chains) && Array.isArray(relayStatus.blockFetchStatus);
  const relayHealthy = relayAvailable && relayHealth.status === 'healthy' && relayStatus.service === 'order-sink'
    && fresh(relayHealth.timestamp, now) && fresh(relayStatus.timestamp, now);
  if (!relayHealthy) failures.push('Relay: unavailable, unhealthy, stale, or invalid health/status response');
  const polled = new Set((relayStatus?.takerFetchStats ?? []).filter(s => s.requestCount > 0 && fresh(s.lastFetchAt, now)).map(s => s.serverId));
  const activeTakers = (takers ?? []).filter(t => t.takerType === 'safo_taker' && t.failoverActive === true
    && fresh(t.Timestamp, now) && polled.has(t.nodeAddress));
  if (!activeTakers.length) failures.push('Takers: no fresh active SAFO taker with recent relay polling');

  const integrations = new Map();
  const dependencyRows = [];
  for (const [id, chainConfig] of Object.entries(config)) {
    if (id === '*') continue;
    const live = runtime.get(id);
    const chain = chainNames.get(id) ?? id;
    const chainErrors = rpcErrors.filter(r => idsByLabel.get(r[1]) === id);
    const contractsUnknown = chainErrors.some(r => !r[2].startsWith('oracle'));
    const oracleUnknown = chainErrors.some(r => r[2].startsWith('oracle') || r[2] === 'onchain');
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
    if (live && !readyNetworks.length) {
      failures.push(`${chain}: taker network/refinery/solver adapters unavailable or mismatched (${Object.keys(expectedSolvers).join(',') || 'shared'})`);
    }
    const dexes = Object.entries({ ...config['*']?.dex, ...chainConfig.dex });
    const chainChecks = [];
    for (const [key, dex] of dexes) {
      const name = integrationKey(key);
      const contracts = live && !contractsUnknown ? live[3] === 'supported' && deployed.get(`${id}:${name}`) === true : null;
      const oracle = live && !oracleUnknown ? live[6].startsWith('ok ') : null;
      const relay = !live || !relayAvailable ? null : Boolean(listenerReady
        && relayChain.exchanges?.some(e => sameAddress(e.address, dex.adapter)));
      const taker = !live || !takers || !relayStatus ? null : readyNetworks.some(n => Object.entries(n.running?.dexes ?? {})
        .some(([key, metrics]) => integrationKey(key) === name && fresh(metrics.lastOnBlocksExecution, now, 180_000)
          && (metrics.lastScannedBlockAge ?? 0) <= 120_000 && Object.keys(metrics.errors ?? {}).length === 0));
      if (contracts && relay !== true) failures.push(`${chain}/${key}: relay adapter unregistered or listener unavailable`);
      if (contracts && taker !== true) failures.push(`${chain}/${key}: taker loop missing, stale, unhealthy, or metadata mismatched`);
      const checks = { id, contracts, oracle, takers: taker, relay, solver: dex.solver ?? (dex.type === 'universal' ? 'universal' : '') };
      if (!integrations.has(name)) integrations.set(name, []);
      integrations.get(name).push(checks);
      chainChecks.push(checks);
    }
    if (live) {
      const active = chainChecks.filter(c => c.contracts);
      dependencyRows.push([chain, `${active.length}/${dexes.length}`, live[6],
        takers && relayStatus ? `${active.filter(c => c.takers).length}/${active.length}` : 'unknown',
        relayAvailable ? `${active.filter(c => c.relay).length}/${active.length}` : 'unknown']);
    }
  }

  const boardRows = [];
  if (!notionPages) warnings.push('Notion: board unavailable; sync could not be checked');
  else {
    const seen = new Set();
    for (const page of notionPages) {
      const p = page.properties;
      if (normalize(p?.Module?.select?.name) !== 'spot') continue;
      const title = (p.Partner?.title ?? []).map(t => t.plain_text ?? t.text?.content ?? '').join('');
      const name = integrationKey(title);
      if (seen.has(name)) warnings.push(`Notion ${title}: duplicate SPOT row`);
      seen.add(name);
      const checks = integrations.get(name);
      if (!checks) {
        warnings.push(`Notion ${title}: stale SPOT row, integration is unconfigured`);
        boardRows.push([title, 'unconfigured', '-', '-', '-', '-']);
        continue;
      }
      const expectedChains = checks.map(c => c.id).sort();
      const actualChains = (p.Chain?.multi_select ?? []).map(c => chainIds.get(normalize(c.name)) ?? `unknown:${c.name}`).sort();
      const chainsMatch = JSON.stringify(expectedChains) === JSON.stringify(actualChains);
      if (!chainsMatch) warnings.push(`Notion ${title}: Chain mismatch; expected ${expectedChains.join(',')}, found ${actualChains.join(',')}`);
      const row = [title, chainsMatch ? 'ok' : 'mismatch'];
      for (const [key, column] of Object.entries(columns)) {
        const expected = progress(checks.map(c => c[key]));
        const actual = p[column]?.status?.name ?? 'unset';
        row.push(expected === null ? `${actual} / unchecked` : normalize(actual) === normalize(expected) ? actual : `${actual} -> ${expected}`);
        if (expected !== null && normalize(actual) !== normalize(expected)) warnings.push(`Notion ${title}: ${key[0].toUpperCase() + key.slice(1)} is ${actual}; expected ${expected}`);
      }
      const solvers = [...new Set(checks.map(c => c.solver))];
      const expectedSolver = solvers.length === 1 ? normalize(solvers[0]) : '';
      if (normalize(p.Solver?.select?.name) !== expectedSolver) warnings.push(`Notion ${title}: Solver mismatch; expected ${expectedSolver || 'unset (multiple solvers)'}`);
      boardRows.push(row);
    }
    for (const name of integrations.keys()) if (!seen.has(name)) warnings.push(`Notion: missing SPOT row for ${name}`);
  }
  return { dependencyRows, boardRows, failures, warnings };
}

async function main() {
  const records = readFileSync(0, 'utf8').trim().split('\n').filter(Boolean).map(line => line.split('\t'));
  const skill = readFileSync(resolve(root, 'skill/SKILL.md'), 'utf8');
  const relay = skill.match(/https:\/\/[^\s`]+(?=\/orders\/new)/)?.[0];
  if (!relay) throw new Error('Relay endpoint missing from skill');
  const urls = (process.env.SPOT_TAKER_HEALTH_URLS ?? 'http://***REMOVED***:9006/health').split(',').map(s => s.trim()).filter(Boolean);
  const getJson = async url => {
    const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  };
  const sources = await Promise.allSettled([getJson(`${relay}/health`), getJson(`${relay}/status`),
    Promise.all(urls.map(getJson)), readNotion(fetch, process.env.NOTION_API_KEY)]);
  const values = sources.map(result => result.status === 'fulfilled' ? result.value : null);
  const result = evaluate({ config: JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf8')), skill, records,
    relayHealth: values[0], relayStatus: values[1], takers: values[2], notionPages: values[3] });
  sources.forEach((source, i) => {
    if (source.status === 'rejected') (i === 3 ? result.warnings : result.failures).push(`${['Relay health', 'Relay status', 'Taker health', 'Notion'][i]}: request failed (${source.reason.name})`);
  });
  console.log('\n🔎 Live runtime coverage (active integrations; taker polling/loops; relay registration/listeners)');
  printTable(['chain', 'Spot active/configured', 'Oracle', 'Takers', 'Relay'], result.dependencyRows);
  console.log('\n🔎 Notion SPOT sync (actual -> expected)');
  printTable(['integration', 'Chains', 'Contracts', 'Oracle', 'Takers', 'Relay'], result.boardRows);
  if (result.warnings.length) {
    console.log('\n⚠️ Notion sync warnings');
    printTable(['detail'], result.warnings.map(detail => [detail]));
  }
  if (result.failures.length) {
    console.log('\n❌ Runtime failures');
    printTable(['detail'], result.failures.map(detail => [detail]));
    process.exitCode = 1;
  } else console.log('✅ Runtime dependencies match.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('❌ Runtime check failed: invalid input or unavailable dependency'); process.exitCode = 1; });
}
