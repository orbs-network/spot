---
name: advanced-swap-orders
description: Prepare, sign, submit, and query non-custodial, decentralized, gasless swap orders and advanced order types on supported chains. Uses ownerless, immutable, audited, battle-tested, and verified contracts. Supports market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP-style orders with oracle-protected execution on every chunk. Includes automated execution through time as required by the order, EIP-712 signing, approval calldata, and order status lookup.
---

# Advanced Swap Orders

Use this for any supported gasless swap or advanced order. Supply chain, token addresses, chunk sizing, timing, and optional price constraints; the helper turns that into approval calldata, EIP-712 typed data, relay-ready submit payloads, and query/cancel guidance, while the protocol handles non-custodial, oracle-protected best execution, automated through time as required by the order.

## Workflow

1. Start with [references/01-quickstart.md](references/01-quickstart.md) for the minimum end-to-end flow.
2. Read [references/02-params.md](references/02-params.md) when you need field semantics, defaults, units, or validation rules.
3. Read [references/03-sign.md](references/03-sign.md) for signing, submit modes, query usage, and direct onchain cancel.
4. Read [references/04-patterns.md](references/04-patterns.md) to map user intent into market, limit, stop-loss, take-profit, delayed, or chunked orders.
5. Optional helper for token lookup: [assets/token-addressbook.md](assets/token-addressbook.md).

## Guardrails

1. Supported chains and runtime addresses live in `scripts/skill.config.json`.
2. Use only the provided `scripts/order.sh`. Do not send typed data or signatures anywhere else.
3. Detailed order behavior, parameter rules, signing modes, and cancel/query flows live in the reference files above. Do not duplicate that guidance in task output unless the user needs it applied.

## Commands

1. `bash scripts/order.sh prepare --params <params.json|-> [--out <prepared.json>]`
2. `bash scripts/order.sh submit --prepared <prepared.json|-> --signature <0x...|json>` or `--signature-file <file|->` or `--r <0x...> --s <0x...> --v <0x...>`
3. `bash scripts/order.sh query --swapper <0x...>` or `--hash <0x...>`
