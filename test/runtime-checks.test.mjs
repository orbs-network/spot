import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluate } from '../script/runtime-checks.mjs';

const address = '0x1111111111111111111111111111111111111111';
const now = Date.parse('2026-09-14T12:00:00Z');
const timestamp = new Date(now).toISOString();
function fixture() {
  return {
    now, config: { '*': { refinery: address, dex: { agent: { type: 'universal', adapter: address } } }, '1': {} },
    skill: '1. Ethereum - `1`',
    records: [ ['runtime', 'eth', '1', 'supported', '6/6', '1/1', 'ok 3/3', '2/2'], ['dex', 'eth', 'agent', 'universal', '-', '-'] ],
    relayHealth: { status: 'healthy', timestamp },
    relayStatus: { service: 'order-sink', timestamp, chains: [{ chainId: 1, exchanges: [{ name: 'Agent', address }] }],
      blockFetchStatus: [{ chainId: 1, eventsFetchingEnabled: true, listenerActive: true, lastBlock: 1, updatedAt: timestamp }],
      takerFetchStats: [{ serverId: 'taker', lastFetchAt: timestamp, requestCount: 2 }] },
    takers: [{ nodeAddress: 'taker', takerType: 'safo_taker', failoverActive: true, Timestamp: timestamp,
      metadata: { networks: { ethereum: { id: '1', addresses: { refinery: address, spot: { routerAdapters: {} } } } } },
      networks: { ethereum: { dexes: { agent: { lastOnBlocksExecution: now, errors: [] } } } } }],
  };
}
test('healthy runtime passes', () => assert.deepEqual(evaluate(fixture()).failures, []));
test('unconfigured taker health is skipped without masking relay failures', () => {
  const data = fixture(); delete data.takers;
  const result = evaluate(data);
  assert.deepEqual(result.failures, []);
  assert.equal(result.dependencyRows[0][3], 'skipped');
  data.relayHealth = null;
  assert.match(evaluate(data).failures.join('\n'), /Relay/);
});
test('configured taker health with unavailable or empty responses still fails', () => {
  for (const takers of [null, []]) {
    const data = fixture(); data.takers = takers;
    assert.match(evaluate(data).failures.join('\n'), /Takers:/);
  }
});
test('relay adapter registration is checked by address', () => {
  const data = fixture(); data.relayStatus.chains[0].exchanges[0].address = '0x2222222222222222222222222222222222222222';
  assert.match(evaluate(data).failures.join('\n'), /relay.*adapter/i);
});
test('disabled or stale relay listeners fail', () => {
  for (const change of [{ listenerActive: false }, { updatedAt: new Date(now - 600_000).toISOString() }]) {
    const data = fixture(); Object.assign(data.relayStatus.blockFetchStatus[0], change);
    assert.match(evaluate(data).failures.join('\n'), /relay.*listener/i);
  }
});
test('takers must be active, polling, and running a fresh integration loop', () => {
  for (const mutate of [d => d.takers[0].failoverActive = false, d => d.relayStatus.takerFetchStats = [],
    d => d.takers[0].networks.ethereum.dexes.agent.lastOnBlocksExecution = now - 600_000,
    d => d.takers[0].networks.ethereum.dexes = {}]) {
    const data = fixture(); mutate(data);
    assert.match(evaluate(data).failures.join('\n'), /taker/i);
  }
});
test('taker solver adapter addresses match Spot', () => {
  const data = fixture(); data.config['1'].adapter = { Solver: address };
  assert.match(evaluate(data).failures.join('\n'), /taker.*Solver/i);
});
test('unavailable runtime sources fail and show unknown coverage', () => {
  const data = fixture(); data.relayHealth = null; data.relayStatus = null; data.takers = null;
  const result = evaluate(data);
  assert.match(result.failures.join('\n'), /Relay:/);
  assert.match(result.failures.join('\n'), /Takers:/);
  assert.deepEqual(result.dependencyRows[0].slice(3), ['unknown', 'unknown']);
});
test('additional relay chains do not restore removed Spot support', () => {
  const data = fixture(); data.relayStatus.chains.push({ chainId: 5000, exchanges: [{ address }] });
  const result = evaluate(data);
  assert.deepEqual(result.failures, []);
  assert.equal(result.dependencyRows.length, 1);
});
