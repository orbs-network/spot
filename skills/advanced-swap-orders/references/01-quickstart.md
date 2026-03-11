# Quickstart

1. Required fields: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Read [02-params.md](02-params.md) for defaults, units, chunking semantics, native asset rules, and validation notes.
3. Read [04-patterns.md](04-patterns.md) to choose the right market, limit, stop-loss, take-profit, delayed, or chunked shape.
4. Prepare: `bash scripts/order.sh prepare --params <params.json|->`
5. If approval is needed, send `prepared.approval.tx`.
6. Sign `prepared.typedData` as the `swapper`.
7. Read [03-sign.md](03-sign.md) for signature formats, submit modes, query usage, and direct onchain cancel.
8. Submit: `bash scripts/order.sh submit --prepared <prepared.json|-> --signature <0x...|json>`
9. Query: `bash scripts/order.sh query --swapper <0x...>` or `--hash <0x...>`
