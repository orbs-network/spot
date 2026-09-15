import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluate, readNotion, formatNotion } from '../script/runtime-checks.mjs';

const address = '0x1111111111111111111111111111111111111111';
const now = Date.parse('2026-09-14T12:00:00Z');
const timestamp = new Date(now).toISOString();
const status = name => ({ status: { name } });
const page = () => ({ properties: {
  Partner: { title: [{ plain_text: 'Agent' }] }, Module: { select: { name: 'SPOT' } },
  Chain: { multi_select: [{ name: 'Ethereum' }] }, Solver: { select: { name: 'universal' } },
  Contracts: status('Done'), Oracle: status('Done'),
  'Takers': status('Done'), Relay: status('Done'),
} });
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
    notionPages: [page()],
  };
}
test('healthy runtime and matching board pass', () => assert.deepEqual(evaluate(fixture()).failures, []));
test('Notion output groups fixes by column and target status, combining identical groups', () => {
  assert.equal(formatNotion([
    'Notion Katana: Contracts is Not started; expected Done',
    'Notion Katana: Oracle is Not started; expected Done',
    'Notion Ginco: Contracts is Not started; expected Done',
    'Notion Ginco: Oracle is Not started; expected Done',
    'Notion Katana: Takers is Not started; expected Done',
    'Notion Ginco: Takers is Not started; expected In progress',
    'Notion Chronos: stale SPOT row, integration is unconfigured',
    'Notion Arbidex: stale SPOT row, integration is unconfigured',
  ]), '⚠️ Notion SPOT fixes\n\n1. Contracts + Oracle → Done: Katana, Ginco\n2. Takers → Done: Katana\n3. Takers → In progress: Ginco\n4. Review stale rows: Chronos, Arbidex');
});
test('Notion output retains other diagnostics and has a concise clean result', () => {
  assert.equal(formatNotion([]), '✅ Notion SPOT: no fixes detected.');
  const warnings = ['Notion: board unavailable; sync could not be checked',
    'Notion: request failed (Error)', 'Notion Agent: duplicate SPOT row',
    'Notion: missing SPOT row for ring', 'Notion Agent: Chain mismatch; expected 1, found 10',
    'Notion Agent: Solver mismatch; expected universal'];
  const output = formatNotion(warnings);
  for (const warning of warnings) assert.ok(output.includes(warning));
  assert.doesNotMatch(output, /no fixes detected/);
});
test('unconfigured taker health is skipped without masking relay failures or changing board readiness', () => {
  const data = fixture(); delete data.takers;
  const result = evaluate(data);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.warnings, []);
  assert.equal(result.dependencyRows[0][3], 'skipped');
  assert.equal(data.notionPages[0].properties.Takers.status.name, 'Done');
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
test('Notion compares all four columns and chain membership', () => {
  for (const column of ['Contracts', 'Oracle', 'Takers', 'Relay']) {
    const data = fixture(); data.notionPages[0].properties[column] = status('Not started');
    assert.deepEqual(evaluate(data).failures, []);
    assert.match(evaluate(data).warnings.join('\n'), new RegExp(column));
  }
  const data = fixture(); data.notionPages[0].properties.Chain.multi_select = [{ name: 'Mantle' }];
  assert.match(evaluate(data).warnings.join('\n'), /Notion.*Chain/);
});
test('missing, duplicate, and stale SPOT rows warn; other modules are ignored', () => {
  const missing = fixture(); missing.notionPages = [];
  assert.match(evaluate(missing).warnings.join('\n'), /missing.*Notion|Notion.*missing/i);
  const duplicate = fixture(); duplicate.notionPages.push(page());
  assert.match(evaluate(duplicate).warnings.join('\n'), /duplicate/i);
  const stale = fixture(); stale.notionPages[0].properties.Partner.title[0].plain_text = 'Removed';
  assert.match(evaluate(stale).warnings.join('\n'), /unconfigured|stale/i);
  const unrelated = fixture(); const row = page(); row.properties.Module.select.name = 'TWAP'; unrelated.notionPages.push(row);
  assert.deepEqual(evaluate(unrelated).warnings, []);
});
test('oracle failures are reflected in Notion, without changing the board', () => {
  const data = fixture(); data.records[0][6] = 'failed 2/3';
  assert.match(evaluate(data).warnings.join('\n'), /Notion.*Oracle/);
  assert.equal(data.notionPages[0].properties.Oracle.status.name, 'Done');
});
test('source outages remain unknown rather than inventing Notion statuses', () => {
  const data = fixture(); data.relayHealth = null; data.relayStatus = null; data.takers = null;
  const result = evaluate(data);
  assert.match(result.failures.join('\n'), /relay|taker/i);
  assert.doesNotMatch(result.warnings.join('\n'), /Notion.*Relay/);
});
test('onchain RPC failures do not invent board deployment statuses', () => {
  const data = fixture(); data.records[0][3] = 'unsupported';
  data.records.push(['issue', 'eth', 'core', '5/6; wm:rpc-error']);
  assert.doesNotMatch(evaluate(data).warnings.join('\n'), /Notion.*Contracts/);
});
test('partial and scoped coverage produce distinct board expectations', () => {
  const data = fixture(); data.config['10'] = {}; data.skill += '\n2. Optimism - `10`';
  data.notionPages[0].properties.Chain.multi_select.push({ name: 'Optimism' });
  assert.doesNotMatch(evaluate(data).warnings.join('\n'), /Notion.*Contracts/);
  data.records.push(['runtime', 'op', '10', 'unsupported', '0/6', '0/1', 'failed 0/3', '-']);
  assert.match(evaluate(data).warnings.join('\n'), /Contracts is Done; expected In progress/);
});
test('additional relay chains do not restore removed Spot support', () => {
  const data = fixture(); data.relayStatus.chains.push({ chainId: 5000, exchanges: [{ address }] });
  const result = evaluate(data);
  assert.deepEqual(result.failures, []);
  assert.equal(result.dependencyRows.length, 1);
});
test('Notion auth and broken pagination fail closed', async () => {
  await assert.rejects(readNotion(() => assert.fail('must not request without a token'), ''), /NOTION_API_KEY/);
  await assert.rejects(readNotion(async () => ({ ok: false, status: 401 }), 'test-token'), /HTTP 401/);
  await assert.rejects(readNotion(async () => ({ ok: true, json: async () => ({ results: [], has_more: true, next_cursor: 'same' }) }), 'test-token'), /cursor/);
});
test('Notion pagination reads every page without mutation', async () => {
  const requests = [];
  const fetcher = async (url, options) => {
    requests.push({ url, ...options });
    return { ok: true, json: async () => ({ results: [page()], has_more: requests.length === 1, next_cursor: 'next' }) };
  };
  const pages = await readNotion(fetcher, 'test-token');
  assert.equal(pages.length, 2);
  assert.ok(requests.every(r => r.method === 'POST' && r.url.endsWith('/query')));
  assert.equal(JSON.parse(requests[1].body).start_cursor, 'next');
});

test('Notion unavailability is a warning, while runtime failures still fail', () => {
  const data = fixture(); data.notionPages = null;
  assert.deepEqual(evaluate(data).failures, []);
  assert.match(evaluate(data).warnings.join('\n'), /Notion.*unavailable/);
  data.relayHealth = null;
  assert.match(evaluate(data).failures.join('\n'), /Relay/);
});
