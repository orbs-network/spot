---
name: spot-advanced-swap-orders
description: Use for gasless non-custodial EVM market, limit, TWAP, stop-loss, take-profit, delayed-start swaps.
version: 2.6.0
author: Orbs Network
license: MIT
metadata:
  hermes:
    tags: [DeFi, EVM, swaps, limit-orders, TWAP, stop-loss, Ethereum, Polygon, Base, Arbitrum, Avalanche, BNB, crypto, Web3]
    category: blockchain
    related_skills: [evm]
---

# Spot Advanced Swap Orders

Use this skill when the agent needs to turn user intent into a final Spot order payload on a supported EVM chain.
It covers order-shape selection, param normalization, typed-data population, approval guidance, signing, submission, query, and cancellation.
This bundle is instruction-only: build everything locally from the bundled markdown and JSON assets, then submit only the final signed payload.
Execution remains decentralized, non-custodial, oracle-protected, immutable, audited, and battle-tested onchain.

## Supported Chains

1. Ethereum - `1`
2. BNB Chain - `56`
3. Polygon - `137`
4. Sonic - `146`
5. Base - `8453`
6. Arbitrum One - `42161`
7. Avalanche - `43114`
8. Linea - `59144`

The bundled JSON template hardcodes the shared agent adapter. Do not derive or replace the adapter per chain.

## Relay

1. Submit signed orders with `POST https://agents-sink.orbs.network/orders/new`.
2. Query orders with `GET https://agents-sink.orbs.network/orders`; see [references/lifecycle.md](references/lifecycle.md) for filters, polling, and cancellation follow-up.

## Workflow

1. Read [references/quickstart.md](references/quickstart.md) for the minimum end-to-end flow.
2. Use [references/params.md](references/params.md) to map user intent into params, defaults, validation, and order-shape fields.
3. Use [references/sign.md](references/sign.md) to fill the template, handle approval, sign, and submit.
4. Use [references/lifecycle.md](references/lifecycle.md) for relay query semantics, status polling, and cancellation.
5. Use [references/examples.md](references/examples.md) only when the final relay payload shape is still unclear.
6. Use [assets/token-addressbook.md](assets/token-addressbook.md) only for optional token alias lookup on supported chains.
7. Use [assets/repermit.template.json](assets/repermit.template.json) as the canonical typed-data shape.
8. Treat `## Supported Chains` as the authoritative source for chain support.
9. Treat `## Relay` as the authoritative relay endpoint list.

## Guardrails

1. `## Supported Chains` is authoritative for chain support.
2. `## Relay` is authoritative for relay endpoints.
3. [assets/token-addressbook.md](assets/token-addressbook.md) is a convenience alias list only. It does not expand chain support or override explicit user-provided addresses.
4. This skill is instruction-only. Do not fetch or execute external helper code.
5. Normalize params with [references/params.md](references/params.md) before touching the template.
6. Replace only the `<...>` placeholders in [assets/repermit.template.json](assets/repermit.template.json). Keep the fixed protocol fields already in the template unchanged.
7. Default approval guidance is exact `approve(..., input.maxAmount)`. Standing `maxUint256` approval is opt-in convenience for repeat use, not the default suggestion.
8. Submit only the final signed payload as described in [references/sign.md](references/sign.md).

## Agent Contract

1. Turn the user request into a params JSON object using [references/params.md](references/params.md).
2. Normalize params locally, including defaults, rounding, and order-shape fields.
3. Confirm `chainId` is listed in `## Supported Chains`, then populate [assets/repermit.template.json](assets/repermit.template.json) from the normalized params while keeping the hardcoded adapter unchanged.
4. Handle approval, signing, and submission exactly as described in [references/sign.md](references/sign.md), and forward the returned signature unchanged.
5. Query and cancel exactly as described in [references/lifecycle.md](references/lifecycle.md).
