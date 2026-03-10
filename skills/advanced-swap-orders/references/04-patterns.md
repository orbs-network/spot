# Order Patterns

1. Market swap: `input.amount = input.maxAmount`, `output.limit = 0`.
2. Limit order: `input.amount = input.maxAmount`, `output.limit > 0`.
3. Stop-loss or take-profit: set `output.triggerLower` and/or `output.triggerUpper`.
4. Delayed order: set future `start`.
5. Chunked or TWAP-style: set `input.amount < input.maxAmount`.
6. Time-spaced chunked order: set `epoch > 0`.
7. Native output: set `output.token = 0x0000000000000000000000000000000000000000`.
8. Best execution and oracle protection apply regardless of `output.limit`.
