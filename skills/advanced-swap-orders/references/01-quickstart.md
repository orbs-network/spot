# Quickstart

1. Required: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`. `input.maxAmount` is optional and defaults to `input.amount`.
2. `input.amount` is the fixed per-chunk size. `input.maxAmount` is total size and approval amount. If `input.maxAmount` is not divisible by `input.amount`, the helper rounds `input.maxAmount` down to a whole number of chunks.
3. `input.amount == input.maxAmount` means single-fill. Smaller `input.amount` means chunked or TWAP-style.
4. Future `start` delays the first fill. `epoch > 0` sets the delay between chunks, but it is not exact: each chunk can fill anywhere inside its epoch window, only once. `epoch = 0` is immediate single-fill only.
5. `epoch = 60` means one chunk can fill once anywhere inside each 60-second epoch window.
6. `output.limit = 0` means market-style. `output.limit > 0` means limit-style. `output.limit`, `output.triggerLower`, and `output.triggerUpper` are output-token units per chunk.
7. Best execution and oracle protection apply to every order and every chunk, regardless of `output.limit`.
8. Defaults: `nonce=now`, `start=now`, `deadline=start + 300 + chunkCount * epoch` as a conservative helper default, `slippage=500`, `recipient=swapper`, `limit=0`.
9. Native input is not supported. Wrap to WNATIVE first. Native output is supported with `output.token = 0x0000000000000000000000000000000000000000`.
10. Use only the provided helper script. Do not send typed data or signatures anywhere else.
11. Flow: `bash scripts/order.sh prepare --params <params.json|->`, wrap native if needed, send `prepared.approval.tx` if needed, sign `prepared.typedData`, submit, then query by `--swapper` or `--hash`.
12. Piping works: `cat params.json | bash scripts/order.sh prepare --params -`.
