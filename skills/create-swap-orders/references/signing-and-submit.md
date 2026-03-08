# Signing And Submit

Use this reference only after `prepare` has already produced `prepared.json`.

Signing and submission are the gasless part of the flow. The approval transaction is the only onchain step here when approval is not already in place.

## Sign

1. Sign `prepared.json.typedData`.
2. Prefer `eth_signTypedData_v4`.
3. Use `prepared.json.signing.params` directly when the wallet expects JSON-RPC params.
4. Keep the signing account equal to `swapper`.
5. Do not hand-build typed-data fields if `prepared.json.signing` already exists.
6. Submit `prepared.json.typedData.message` as `order`. Do not submit the full typed-data object to the API.

## Browser Example

Use `assets/web3-sign-and-submit.example.js` when a browser or injected wallet flow is needed.

It:

1. Sends the approval tx.
2. Requests the EIP-712 signature.
3. Splits the signature into `v`, `r`, and `s`.
4. Posts the final body to the relay.

## Submit With CLI

Use split signature format by default because the documented API expects:

```json
{
  "signature": {
    "v": "0x1b",
    "r": "0x...",
    "s": "0x..."
  }
}
```

Default create-order submit:

`node skills/create-swap-orders/scripts/order_flow.js submit --prepared <prepared.json> --signature <0x...>`

Raw signature override:

`node skills/create-swap-orders/scripts/order_flow.js submit --prepared <prepared.json> --signature <0x...> --format raw`

Split `v/r/s` dry run:

`node skills/create-swap-orders/scripts/order_flow.js submit --prepared <prepared.json> --signature <0x...> --format split --dry-run`

## POST Body

The helper submits:

```json
{
  "order": { "...typedDataMessage": "..." },
  "signature": {
    "v": "0x1b",
    "r": "0x...",
    "s": "0x..."
  }
}
```

Use `--format split` if the receiver needs:

```json
{
  "order": { "...typedData": "..." },
  "signature": {
    "r": "0x...",
    "s": "0x...",
    "v": "0x1b"
  }
}
```

## Query Existing Orders

Query by swapper and chain:

`node skills/create-swap-orders/scripts/order_flow.js query --swapper <0x...> --chainId <id> --limit 10`

Query by hash:

`node skills/create-swap-orders/scripts/order_flow.js query --hash <0x...>`
