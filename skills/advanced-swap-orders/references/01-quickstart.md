# Quickstart

1. Required fields: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Read [02-params.md](02-params.md) for defaults, units, chunking semantics, native asset rules, and validation notes.
3. Read [04-patterns.md](04-patterns.md) to choose the right market, limit, stop-loss, take-profit, delayed, or chunked shape.
4. Prepare: `bash scripts/order.sh prepare --params <params.json|->`
5. Piping works: `cat params.json | bash scripts/order.sh prepare --params -`
6. If approval is needed, send `prepared.approval.tx`.
7. Sign `prepared.typedData` as the `swapper`.
8. Read [03-sign.md](03-sign.md) for signature formats, submit modes, `--dry-run`, query usage, and direct onchain cancel.
9. Submit: `bash scripts/order.sh submit --prepared <prepared.json|-> --signature <0x...|json>`
10. Query: `bash scripts/order.sh query --swapper <0x...>` or `--hash <0x...>`
11. Approval strategy: exact approval works, but for repeat use you can set infinite approval to `RePermit` so users avoid re-approving every order. The signed witness still constrains each spend to the specific order.
