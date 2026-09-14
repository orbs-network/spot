import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { formatTable } from '../script/table.mjs';

const headers = ['chain', 'id', 'Spot', 'core', 'adapters deployed/known', 'oracle contracts', 'USD quotes'];
const rows = [['robinhood', '46630', 'yes', '6/6', '8/8', '3/3', 'USDG: 1000000000000000000']];

for (const columns of [5, 24, 40, 80, 120]) {
  test(`coverage table fits ${columns} columns without losing cell contents`, () => {
    const output = formatTable(headers, rows, columns);
    const lines = output.split('\n');
    assert.ok(lines.every(line => line.length <= columns));
    assert.ok(lines.every(line => /^[┌├└│]/u.test(line)));
    if (columns < 4 * headers.length + 1) {
      const content = output.replace(/[┌┬┐─├┼┤└┴┘│\s]/gu, '');
      for (const value of [...headers, ...rows[0]]) assert.ok(content.includes(value.replace(/\s/g, '')));
    } else {
      const groups = output.split(/\n├[^\n]+\n/u);
      for (const [i, expected] of [headers, rows[0]].entries()) {
        const body = groups[i].split('\n').filter(line => line.startsWith('│')).map(line => line.split('│').slice(1, -1));
        expected.forEach((value, col) => assert.equal(body.map(line => line[col].trim()).join('').replace(/\s/g, ''), value.replace(/\s/g, '')));
      }
    }
  });
}

test('piped TSV respects terminal columns and preserves a long address', () => {
  const address = `0x${'1234567890'.repeat(4)}`;
  const result = spawnSync(process.execPath, ['script/table.mjs'], {
    input: `chain\tdetail\nethereum\t${address}\n`, encoding: 'utf8', env: { ...process.env, COLUMNS: '40' },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.trimEnd().split('\n').every(line => line.length <= 40));
  assert.ok(result.stdout.replace(/[┌┬┐─├┼┤└┴┘│\s]/gu, '').includes(address));
});
