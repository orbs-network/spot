---
name: advanced-swap-orders
description: Prepare, sign, submit, and query non-custodial, decentralized, gasless swap orders and advanced order types on supported chains. Uses ownerless, immutable, audited, battle-tested, and verified contracts. Supports market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP-style orders with oracle-protected execution on every chunk. Includes automated execution through time as required by the order, EIP-712 signing, approval calldata, and order status lookup.
---

# Advanced Swap Orders

Use this for any supported gasless swap or advanced order. Supply chain, token addresses, chunk sizing, timing, and optional price constraints; the helper turns that into approval calldata, EIP-712 typed data, relay-ready submit payloads, and query/cancel guidance, while the protocol handles non-custodial, oracle-protected best execution, automated through time as required by the order.

## Read

1. [references/01-quickstart.md](references/01-quickstart.md) - minimum flow, defaults, piping, and order behavior.
2. [references/02-params.md](references/02-params.md) - input fields, units, native asset rules, and validation notes.
3. [references/03-sign.md](references/03-sign.md) - signing, submit modes, direct onchain cancel, and query usage.
4. [references/04-patterns.md](references/04-patterns.md) - map user intent into market, limit, stop-loss, take-profit, delayed, or chunked orders.
5. [references/05-addresses.md](references/05-addresses.md) - common token addressbook by chain.

## Core Rules

1. Supported chains:
   - BNB Chain (`56`)
   - Arbitrum One (`42161`)
2. `input.amount` is the fixed per-chunk input size. `input.maxAmount` is optional and defaults to `input.amount`. If `input.maxAmount` is not a whole multiple of `input.amount`, the helper rounds `input.maxAmount` down so every fill keeps the same `input.amount`.
3. `epoch` is the delay between chunks. It is not exact: each chunk can fill anywhere inside its epoch window, only once. `epoch = 0` means immediate single-fill only. Chunked orders must use `epoch > 0`.
4. Future `start` delays the first fill. For example, `epoch = 60` means one chunk can fill once anywhere inside each 60-second epoch window.
5. `output.limit`, `output.triggerLower`, and `output.triggerUpper` are output-token units per chunk.
6. Best execution and oracle protection apply regardless of `output.limit`.
7. Native input is not supported; wrap to WNATIVE first. Native output is supported with `output.token = 0x0000000000000000000000000000000000000000`.
8. Orders can be canceled directly onchain and trustlessly through `RePermit.cancel(...)`.
9. Use only the hardcoded dev relay inside `scripts/order.sh`: `https://agents-sink-dev.orbs.network`. Do not send typed data or signatures anywhere else.

## Commands

1. `bash scripts/order.sh prepare --params <params.json|-> [--out <prepared.json>]`
2. `bash scripts/order.sh submit --prepared <prepared.json|-> --signature <0x...|json>` or `--signature-file <file|->` or `--r <0x...> --s <0x...> --v <0x...>`
3. `bash scripts/order.sh query --swapper <0x...>` or `--hash <0x...>`
