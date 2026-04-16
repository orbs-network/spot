# Params

Use this file for field semantics, order-shape mapping, defaults, validation, and local normalization.

1. Required: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Optional: `input.maxAmount`, `nonce`, `start`, `deadline`, `epoch`, `slippage`, `output.limit`, `output.triggerLower`, `output.triggerUpper`, `output.recipient`.
3. Common order-shape fields: market = `output.limit = 0`; limit = `output.limit > 0`; stop-loss = `output.triggerLower > 0`; take-profit = `output.triggerUpper > 0`; delayed-start = future `start`; chunked or TWAP = `input.amount < input.maxAmount`; recurring chunked = `epoch > 0`; back to native output = `output.token = 0x0000000000000000000000000000000000000000`.
4. `input.amount` is the fixed per-chunk size. `input.maxAmount` is the total requested size. If omitted, it defaults to `input.amount`. If it is not divisible by `input.amount`, round it down to a whole number of chunks before building `typedData`.
5. `output.limit`, `output.triggerLower`, and `output.triggerUpper` are output-token amounts per chunk, encoded in the output token's decimals.
6. Future `start` delays the first fill. `epoch` is the delay between chunks, but it is not exact: each chunk can fill anywhere inside its epoch window, only once. Large `epoch` is not a delayed order by itself.
7. Chunked orders should use `epoch > 0`; with `epoch = 0`, only the first chunk can fill.
8. Defaults:
   `input.maxAmount = input.amount`, `nonce = now`, `start = now`, `epoch = 0` for single orders, `epoch = 60` for chunked orders, `deadline = start + 300 + chunkCount * epoch`, `slippage = 500`, `output.limit = 0`, `output.triggerLower = 0`, `output.triggerUpper = 0`, `output.recipient = swapper`.
9. Validation:
   `start != 0`, `input.amount != 0`, `input.amount <= input.maxAmount`, `input.token != output.token`, `output.triggerLower <= output.triggerUpper` when `triggerUpper != 0`, `slippage <= 5000`, non-zero `epoch >= 31`, and `freshness = 30 < epoch` when `epoch != 0`.
10. Higher slippage is still protected by oracle pricing and offchain executors.
11. `output.recipient` is dangerous to change away from `swapper`.
12. Native input is not supported. Wrap to WNATIVE first. Native output, including back-to-native orders, is supported directly with `output.token = 0x0000000000000000000000000000000000000000`.
13. Derived execution values:
    `chunkCount = floor(input.maxAmount / input.amount)` after any rounding down.
14. JSON typing:
    keep addresses and byte strings as `0x` strings,
    keep large integer fields as decimal strings,
    use JSON numbers for `domain.chainId`, `message.witness.chainid`, `message.witness.exclusivity`, `message.witness.epoch`, `message.witness.slippage`, `message.witness.freshness`, and `message.witness.exchange.share`.
15. For full mock relay payloads, see [04-examples.md](04-examples.md).
