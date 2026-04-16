---
name: spot-advanced-swap-orders
description: Use for gasless non-custodial EVM market, limit, TWAP, stop-loss, take-profit, delayed-start swaps.
---

# Spot Advanced Swap Orders

Use this for gasless market swaps and advanced orders on supported EVM chains.
Choose this skill when a user wants market, limit, TWAP, stop-loss, take-profit, or delayed-start execution, or needs to prepare, sign, submit, query, or cancel one of those orders.
Supply chain, token addresses, chunk sizing, timing, and optional price constraints.
The helper turns that into approval calldata, EIP-712 typed data, relay-ready submit payloads, and query/cancel guidance,
while decentralized, non-custodial, oracle-protected, immutable, audited, battle-tested contracts handle execution.

## Config

```json
{
  "references": [
    "references/01-quickstart.md",
    "references/02-params.md",
    "references/03-sign.md",
    "references/04-patterns.md"
  ],
  "scripts": [
    "scripts/order.js"
  ],
  "assets": [
    "assets/token-addressbook.md",
    "assets/repermit.skeleton.json",
    "assets/web3-sign-and-submit.example.js"
  ],
  "runtime": {
    "url": "https://agents-sink.orbs.network",
    "contracts": {
      "zero": "0x0000000000000000000000000000000000000000",
      "repermit": "0x00002a9C4D9497df5Bd31768eC5d30eEf5405000",
      "reactor": "0x000000b33fE4fB9d999Dd684F79b110731c3d000",
      "executor": "0x000642A0966d9bd49870D9519f76b5cf823f3000"
    },
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
2. Read [references/02-params.md](references/02-params.md) when you need field semantics, defaults, units, or validation rules.
3. Read [references/03-sign.md](references/03-sign.md) for signing, signature formats, and direct onchain cancel.
4. Read [references/04-patterns.md](references/04-patterns.md) to map user intent into market, limit, stop-loss, take-profit, delayed, or chunked orders.
5. Optional helper for token lookup: [assets/token-addressbook.md](assets/token-addressbook.md).
6. Use [assets/repermit.skeleton.json](assets/repermit.skeleton.json) when you need the raw RePermit witness typed-data skeleton.
7. Use [assets/web3-sign-and-submit.example.js](assets/web3-sign-and-submit.example.js) for a browser or injected-provider signing and submit example.
8. Inspect the frontmatter and `## Config` JSON block in [`SKILL.md`](SKILL.md) for machine-readable metadata, the live supported-chain matrix, sink URL, and runtime contract addresses.
9. Use only [scripts/order.js](scripts/order.js) to prepare, submit, query, and watch orders.

## Guardrails

1. Supported chains and runtime addresses live in the `## Config` JSON block in [`SKILL.md`](SKILL.md).
2. Use only the provided [scripts/order.js](scripts/order.js). Do not send typed data or signatures anywhere else.
3. Use [references/02-params.md](references/02-params.md) as the authoritative source for native-asset rules and for `output.limit` / trigger units.
4. Detailed order behavior, parameter rules, signing rules, and order-shape guidance live in the reference files above.

## Commands

1. Prepare: `node scripts/order.js prepare --params <params.json|-> [--out <prepared.json>]`
2. Submit: `node scripts/order.js submit --prepared <prepared.json|-> --signature <0x...|json>`
3. Submit variants: `--signature-file <file|->` or `--r <0x...> --s <0x...> --v <0x...>`
4. Query: `node scripts/order.js query --swapper <0x...>` or `--hash <0x...>`
5. Watch: `node scripts/order.js watch --hash <0x...> [--interval <seconds>] [--timeout <seconds>]`
