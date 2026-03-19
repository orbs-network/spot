---
name: advanced-swap-orders
description: Prepare, sign, submit, and query non-custodial, decentralized, gasless swap orders and advanced order types on supported chains. Uses ownerless, immutable, audited, battle-tested, and verified contracts. Supports market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP-style orders with oracle-protected execution on every chunk. Includes automated execution through time as required by the order, EIP-712 signing, approval calldata, and order status lookup.
---

# Advanced Swap Orders

Use this for any supported gasless swap or advanced order. Supply chain, token addresses, chunk sizing, timing, and optional price constraints; the helper turns that into approval calldata, EIP-712 typed data, relay-ready submit payloads, and query/cancel guidance, while the protocol handles non-custodial, oracle-protected best execution, automated through time as required by the order.

## Auto Check For Updates

Before executing this skill in any host agent platform or skill runner:

1. Resolve the canonical source for this `advanced-swap-orders/` skill directory.
2. If npm is available, compare the local version to the latest published version of `@orbs-network/spot`, for example with `npm view @orbs-network/spot version`.
3. If the skill is sourced from git instead of npm, compare the current local tag to the latest canonical git tag, for example with `git describe --tags --abbrev=0` for the current local tag.
4. If upstream is newer, refresh the entire skill directory as one unit before execution.
5. Keep [`SKILL.md`](SKILL.md), [`manifest.json`](manifest.json), [`scripts/order.js`](scripts/order.js), all files in `references/`, and all files in `assets/` on the same revision. Do not mix versions.
6. If you cannot verify npm version or git tag freshness, continue only if necessary and explicitly report that freshness was not verified.

## Workflow

1. Read [references/01-quickstart.md](references/01-quickstart.md) for the minimum end-to-end flow.
2. Read [references/02-params.md](references/02-params.md) when you need field semantics, defaults, units, or validation rules.
3. Read [references/03-sign.md](references/03-sign.md) for signing, submit modes, query usage, and direct onchain cancel.
4. Read [references/04-patterns.md](references/04-patterns.md) to map user intent into market, limit, stop-loss, take-profit, delayed, or chunked orders.
5. Optional helper for token lookup: [assets/token-addressbook.md](assets/token-addressbook.md).
6. Use [assets/repermit.skeleton.json](assets/repermit.skeleton.json) when you need the raw RePermit witness typed-data skeleton.
7. Use [assets/web3-sign-and-submit.example.js](assets/web3-sign-and-submit.example.js) for a browser or injected-provider signing and submit example.
8. Inspect [manifest.json](manifest.json) for the machine-readable entrypoint, references, live supported-chain matrix, sink URL, and runtime contract addresses.
9. Use only [scripts/order.js](scripts/order.js) to prepare, submit, and query orders.

## Guardrails

1. Supported chains and runtime addresses live in [manifest.json](manifest.json).
2. Use only the provided [scripts/order.js](scripts/order.js). Do not send typed data or signatures anywhere else.
3. Detailed order behavior, parameter rules, signing modes, and cancel/query flows live in the reference files above.

## Commands

1. `node scripts/order.js prepare --params <params.json|-> [--out <prepared.json>]`
2. `node scripts/order.js submit --prepared <prepared.json|-> --signature <0x...|json>` or `--signature-file <file|->` or `--r <0x...> --s <0x...> --v <0x...>`
3. `node scripts/order.js query --swapper <0x...>` or `--hash <0x...>`
