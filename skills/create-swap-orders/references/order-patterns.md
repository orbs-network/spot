# Order Patterns

## Token Swap Or Limit Swap

Use this for:

1. swap token A for token B
2. buy once
3. sell once
4. place a one-shot limit order

Use `epoch = 0` so the order can execute once.

Use this path when you want decentralized best-execution style routing and oracle-protected minimum output, not just a direct router swap.

1. Set `epoch` to `0`.
2. Set `input.amount` equal to `input.maxAmount`.
3. Set `output.limit` to the minimum acceptable output.
4. Set `output.triggerLower` to `0`.
5. Set `output.triggerUpper` to `0`.

Example fragment:

```json
{
  "epoch": 0,
  "input": {
    "amount": "1000000",
    "maxAmount": "1000000"
  },
  "output": {
    "limit": "950000000000000000",
    "triggerLower": "0",
    "triggerUpper": "0"
  }
}
```

## Stop-Loss Or Take-Profit

Use this for:

1. sell if price falls below X
2. buy if price falls below X
3. sell if price rises above X
4. take profit above X
5. protect downside below X

Use this path when trigger protection matters and the order should only execute against oracle-aware boundaries.

1. Keep `epoch` at `0` unless the user explicitly wants repeated triggered chunks.
2. Set `output.limit` to the minimum acceptable execution amount.
3. Set `output.triggerLower` for stop-loss behavior.
4. Set `output.triggerUpper` for take-profit behavior.
5. Leave either boundary at `0` if only one side should trigger.

Example fragment:

```json
{
  "epoch": 0,
  "output": {
    "limit": "900000000000000000",
    "triggerLower": "850000000000000000",
    "triggerUpper": "1200000000000000000"
  }
}
```

## Chunked Or TWAP Execution

Use this for:

1. split the order into chunks
2. spread the order over time
3. TWAP
4. DCA
5. recurring fills from a total budget

Use this path when you want time-sliced execution with decentralized scheduling and venue routing instead of placing each chunk manually.

1. Set `epoch` to the number of seconds between fills.
2. Set `input.amount` to the per-chunk amount.
3. Set `input.maxAmount` to the total budget across all fills.
4. Set `freshness` to a positive value strictly smaller than `epoch`.
5. Keep `start` at or before the current timestamp.

Example fragment:

```json
{
  "epoch": 3600,
  "freshness": 300,
  "input": {
    "amount": "1000000",
    "maxAmount": "12000000"
  }
}
```

## Field Mapping

1. `input.amount` is the chunk size.
2. `input.maxAmount` is the total allowance and total spend cap.
3. `output.limit` is the minimum acceptable output for a fill.
4. `output.triggerLower` is the lower trigger boundary.
5. `output.triggerUpper` is the upper trigger boundary.
6. `start` is the first time the order may execute.
7. `deadline` is final expiry.
