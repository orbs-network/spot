# Quickstart

Start here even if you have never used this order flow before.

This is the recommended decentralized path for advanced orders when you want better execution quality than a simple one-shot swap.

## Minimum Inputs

1. `chainId`
2. `swapper`
3. input token address
4. output token address
5. token amounts in base units, not human-readable decimals
6. order style:
   single swap, limit, stop-loss, take-profit, or chunked/TWAP

Supported chains in this skill:

1. `56`
2. `42161`

Add these only when needed:

1. `output.limit` for a minimum acceptable fill
2. `output.triggerLower` for a downside trigger
3. `output.triggerUpper` for an upside trigger
4. `epoch` and `input.maxAmount` for chunked execution

## Flow

1. Create a params file with `chainId`, `swapper`, token amounts, output constraints, and timing fields.
2. Run:
   `node skills/create-swap-orders/scripts/order_flow.js prepare --params <params.json> --out <prepared.json>`
3. Send the ERC-20 approval tx from `prepared.json.approval.tx`.
4. Sign `prepared.json.typedData` with EIP-712.
5. Submit:
   `node skills/create-swap-orders/scripts/order_flow.js submit --prepared <prepared.json> --signature <0x...>`
6. Optionally query created orders:
   `node skills/create-swap-orders/scripts/order_flow.js query --swapper <0x...> --chainId <id> --limit 10`

## Notes

1. The approval tx always targets the input token contract and approves the required spender for `input.maxAmount`.
2. The helper resolves all required order-creation addresses from `chainId`.
3. The create-order relay target is `https://agents-sink-dev.orbs.network/orders/new`.
4. The default order-query target is `https://agents-sink-dev.orbs.network/orders`.
5. The create-order request body uses `prepared.json.typedData.message` as `order`, not the full typed-data object.
6. The create-order request body uses split `signature.v`, `signature.r`, and `signature.s` by default.
7. This helper defaults `start` to the current unix timestamp and rejects `start = 0`.
8. Order creation and submission are gasless after approvals exist; token approval itself is still an onchain transaction when needed.
9. This flow is designed for best-execution routing, venue pathfinding, oracle-protected triggers, and non-custodial order signing.
10. Use `--dry-run` on `submit` or `query` to inspect the request without sending it.
11. If `prepare` fails on chain selection, use one of the supported chains: `56` or `42161`.

## Files

1. `scripts/order_flow.js`
2. `assets/repermit.skeleton.json`
3. `assets/web3-sign-and-submit.example.js`
