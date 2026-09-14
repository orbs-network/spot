import { openSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { WriteStream } from 'node:tty';
import { fileURLToPath } from 'node:url';

function terminalWidth() {
  const columns = process.stdout.columns || Number(process.env.COLUMNS);
  if (Number.isInteger(columns) && columns >= 5) return columns;
  try {
    // Reports pipe their input, so inspect the controlling terminal directly.
    const terminal = new WriteStream(openSync('/dev/tty', 'w'));
    const width = terminal.columns;
    terminal.destroy();
    if (width >= 5) return width;
  } catch { /* No controlling terminal when running in CI. */ }
  return 80;
}

export function formatTable(headers, rows, columns = terminalWidth()) {
  if (columns < 4 * headers.length + 1) {
    return formatTable(['record'], rows.length
      ? rows.map(row => [headers.map((header, i) => `${header}: ${row[i] ?? ''}`).join('; ')])
      : headers.map(header => [header]), columns);
  }
  const values = [headers, ...rows].map(row => headers.map((_, i) => String(row[i] ?? '').replace(/[\r\n\t]/g, ' ')));
  const widths = headers.map((_, i) => Math.max(1, ...values.map(row => row[i].length)));
  const available = columns - 3 * headers.length - 1;
  while (widths.reduce((sum, width) => sum + width, 0) > available) {
    widths[widths.indexOf(Math.max(...widths))]--;
  }
  const cells = values.map(row => row.map((value, i) => value.match(new RegExp(`.{1,${widths[i]}}`, 'gu')) ?? ['']));
  const border = (left, middle, right) => left + widths.map(width => '─'.repeat(width + 2)).join(middle) + right;
  const lines = [border('┌', '┬', '┐')];
  cells.forEach((row, i) => {
    for (let line = 0; line < Math.max(...row.map(cell => cell.length)); line++) {
      lines.push('│ ' + row.map((cell, j) => (cell[line] ?? '').padEnd(widths[j])).join(' │ ') + ' │');
    }
    if (i === 0) lines.push(border('├', '┼', '┤'));
  });
  lines.push(border('└', '┴', '┘'));
  return lines.join('\n');
}

export function printTable(headers, rows) {
  console.log(formatTable(headers, rows));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const input = readFileSync(0, 'utf8').trimEnd();
  if (input) {
    const [headers, ...rows] = input.split('\n').map(line => line.split('\t'));
    printTable(headers, rows);
  }
}
