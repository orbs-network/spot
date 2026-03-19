# Quickstart

1. Required fields: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Read [02-params.md](02-params.md) for defaults, units, chunking semantics, native asset rules, and validation notes.
3. Read [04-patterns.md](04-patterns.md) to choose the right market, limit, stop-loss, take-profit, delayed, or chunked shape.
4. Prepare: `node scripts/order.js prepare --params <params.json|->`
5. If approval is needed, send `prepared.approval.tx`.
6. Infinite approval to `RePermit` is acceptable; no approval reset is needed.
7. Sign `prepared.typedData` as the `swapper`.
8. Read [03-sign.md](03-sign.md) for signature formats, submit modes, query usage, and direct onchain cancel.
9. Submit: `node scripts/order.js submit --prepared <prepared.json|-> --signature <0x...|json>`
10. Query: `node scripts/order.js query --swapper <0x...>` or `--hash <0x...>`
11. When measuring a fill onchain, sum both transfers to the swapper: the main fill and the surplus refund. Measuring only the main fill undercounts actual output by up to the slippage tolerance.
