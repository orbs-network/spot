---
name: spot-advanced-swap-orders
description: Use for gasless non-custodial EVM market, limit, TWAP, stop-loss, take-profit, delayed-start swaps.
---

# Spot Advanced Swap Orders

Use this skill when the agent needs to turn user intent into a final Spot order payload on a supported EVM chain.
It covers order-shape selection, param normalization, typed-data population, approval guidance, signing, submission, query, and cancellation.
This bundle is instruction-only: build everything locally from the bundled markdown and JSON assets, then send only the final signed payload to `https://agents-sink.orbs.network/orders/new`.
Execution remains decentralized, non-custodial, oracle-protected, immutable, audited, and battle-tested onchain.

## Config

```json
{
  "references": [
    "references/01-quickstart.md",
    "references/02-params.md",
    "references/03-sign.md",
    "references/04-examples.md"
  ],
  "scripts": [],
  "assets": [
    "assets/token-addressbook.md",
    "assets/repermit.template.json"
  ],
  "runtime": {
    "url": "https://agents-sink.orbs.network",
    "chains": {
      "1": {
        "name": "Ethereum",
        "adapter": "0xC1bB4d5071Fe7109ae2D67AE05826A3fe9116cfc"
      },
      "56": {
        "name": "BNB Chain",
        "adapter": "0x67Feba015c968c76cCB2EEabf197b4578640BE2C"
      },
      "137": {
        "name": "Polygon",
        "adapter": "0x75A3d70Fa6d054d31C896b9Cf8AB06b1c1B829B8"
      },
      "146": {
        "name": "Sonic",
        "adapter": "0x58fD209C81D84739BaD9c72C082350d67E713EEa"
      },
      "8453": {
        "name": "Base",
        "adapter": "0x5906C4dD71D5afFe1a8f0215409E912eB5d593AD"
      },
      "42161": {
        "name": "Arbitrum One",
        "adapter": "0x026B8977319F67078e932a08feAcB59182B5380f"
      },
      "43114": {
        "name": "Avalanche",
        "adapter": "0x4F48041842827823D3750399eCa2832fC2E29201"
      },
      "59144": {
        "name": "Linea",
        "adapter": "0x55E4da2cd634729064bEb294EC682Dc94f5c3f24"
      }
    }
  }
}
```

## Workflow

1. Read [references/01-quickstart.md](references/01-quickstart.md) for the minimum end-to-end flow.
2. Use [references/02-params.md](references/02-params.md) to map user intent into params, defaults, validation, and order-shape fields.
3. Use [references/03-sign.md](references/03-sign.md) to fill the template, handle approval, sign, submit, query, and cancel.
4. Use [references/04-examples.md](references/04-examples.md) only when the final relay payload shape is still unclear.
5. Use [assets/token-addressbook.md](assets/token-addressbook.md) only for optional token alias lookup on supported chains.
6. Use [assets/repermit.template.json](assets/repermit.template.json) as the canonical typed-data shape.
7. Treat the `## Config` JSON block in [`SKILL.md`](SKILL.md) as the authoritative source for supported chains, adapters, and relay URL.

## Guardrails

1. The `## Config` JSON block in [`SKILL.md`](SKILL.md) is authoritative for supported chains, per-chain adapters, and relay URL.
2. [assets/token-addressbook.md](assets/token-addressbook.md) is a convenience alias list only. It does not expand chain support or override explicit user-provided addresses.
3. This skill is instruction-only. Do not fetch or execute external helper code.
4. Normalize params with [references/02-params.md](references/02-params.md) before touching the template.
5. Replace only the `<...>` placeholders in [assets/repermit.template.json](assets/repermit.template.json). Keep the fixed protocol fields already in the template unchanged.
6. Default approval guidance is exact `approve(..., input.maxAmount)`. Standing `maxUint256` approval is opt-in convenience for repeat use, not the default suggestion.
7. Send only the final signed payload to `https://agents-sink.orbs.network/orders/new`.

## Agent Contract

1. Turn the user request into a params JSON object using [references/02-params.md](references/02-params.md).
2. Normalize params locally, including defaults, rounding, and order-shape fields.
3. Populate [assets/repermit.template.json](assets/repermit.template.json) from the normalized params and the adapter for `chainId` from the generated `## Config` JSON block in [`SKILL.md`](SKILL.md).
4. Handle approval and signing exactly as described in [references/03-sign.md](references/03-sign.md), and forward the returned signature unchanged.
