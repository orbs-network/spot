# Quickstart

1. Required: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`. `input.maxAmount` is optional and defaults to `input.amount`.
2. `input.amount` is per-chunk size. `input.maxAmount` is total size and approval amount.
3. `input.amount == input.maxAmount` means single-fill. Smaller `input.amount` means chunked or TWAP-style.
4. Future `start` delays the first fill. `epoch > 0` spaces later chunks. `epoch = 0` is immediate single-fill only.
5. Chunked orders should use `epoch > 0`; otherwise only the first chunk can fill.
6. `output.limit = 0` means market-style. `output.limit > 0` means limit-style. `output.limit`, `output.triggerLower`, and `output.triggerUpper` are output-token units per chunk.
7. Best execution and oracle protection apply to every order and every chunk, regardless of `output.limit`.
8. Defaults: `nonce=now`, `start=now`, `deadline=start + 300 + chunkCount * epoch`, `slippage=500`, `recipient=swapper`, `limit=0`.
9. Native input is not supported. Wrap to WNATIVE first. Native output is supported with `output.token = 0x0000000000000000000000000000000000000000`.
10. Flow: `bash scripts/order.sh prepare --params <params.json|->`, send `prepared.approval.tx` if needed, sign `prepared.typedData`, submit, then query by `--swapper` or `--hash`.
11. Piping works: `cat params.json | bash scripts/order.sh prepare --params -`.
