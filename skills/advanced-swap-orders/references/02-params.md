# Params

1. Required: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Optional: `input.maxAmount`, `nonce`, `start`, `deadline`, `epoch`, `slippage`, `output.limit`, `output.triggerLower`, `output.triggerUpper`, `output.recipient`.
3. `input.amount` is per-chunk size. `input.maxAmount` is total size and approval amount. If omitted, it defaults to `input.amount`.
4. `output.limit`, `output.triggerLower`, and `output.triggerUpper` are output-token units per chunk.
5. Future `start` delays the first fill. `epoch` is chunk cadence after the first fill. Large `epoch` is not a delayed order by itself.
6. Chunked orders should use `epoch > 0`; with `epoch = 0`, only the first chunk can fill.
7. `output.limit = 0` is market-style.
8. `slippage = 500` is the default compromise. Higher slippage is still protected by oracle pricing and offchain executors.
9. `output.recipient` defaults to `swapper` and is dangerous to change.
10. Native input is not supported. Wrap to WNATIVE first. Native output is supported with `output.token = 0x0000000000000000000000000000000000000000`.
11. `nonce` defaults to current unix timestamp in seconds. Routing and protocol constants are fixed inside `scripts/order.sh`.
12. Example:

```json
{
  "chainId": 42161,
  "swapper": "0x1111111111111111111111111111111111111111",
  "input": {
    "token": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "amount": "1000000"
  },
  "output": {
    "token": "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
    "limit": "0"
  },
  "epoch": 3600
}
```
