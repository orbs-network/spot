# Params

Use addresses and base-unit integer amounts only.

Do not pass token symbols like `USDC` or `ETH`.

Do not pass human-readable amounts like `1.5` unless you converted them first.

## Param Shape

```json
{
  "chainId": 42161,
  "swapper": "0x1111111111111111111111111111111111111111",
  "nonce": "1741435200000",
  "start": "1741435200",
  "deadline": "1741521600",
  "exclusivity": 0,
  "epoch": 0,
  "slippage": 100,
  "freshness": 60,
  "input": {
    "token": "0x2222222222222222222222222222222222222222",
    "amount": "1000000",
    "maxAmount": "3000000"
  },
  "output": {
    "token": "0x3333333333333333333333333333333333333333",
    "limit": "950000000000000000",
    "triggerLower": "0",
    "triggerUpper": "0",
    "recipient": "0x1111111111111111111111111111111111111111"
  }
}
```

Omit low-level routing fields unless you already know you need them. The helper fills the normal defaults.

## Inputs To Never Guess

1. token address
2. token decimals
3. base-unit amount
4. signer address
5. target chain

If one of these is missing, gather it before calling the helper.

## Defaults

1. `nonce`: current millisecond timestamp as a decimal string
2. `start`: current unix timestamp
3. `deadline`: `start + 86400`
4. `output.recipient`: `swapper`
5. `exchange.ref`: zero address
6. `exchange.share`: `0`
7. `exchange.data`: `0x`
8. `exclusivity`: `0`
9. `epoch`: `0`
10. `slippage`: `100`
11. `freshness`: `60`, unless `epoch != 0`, then default to a value below `epoch`

## Validation

1. Require `start > 0` and `start <= now`.
2. Require `deadline > now`.
3. Require `input.amount > 0`.
4. Require `input.amount <= input.maxAmount`.
5. Require non-zero `input.token`.
6. Require non-zero `output.recipient`.
7. Require `input.token != output.token`.
8. Require `output.triggerLower <= output.triggerUpper` when `triggerUpper != 0`.
9. Require `slippage <= 5000`.
10. Require `freshness > 0`.
11. Require `freshness < epoch` when `epoch != 0`.
12. Supported chain IDs in this skill are `56` and `42161`.

## Prepared Output

1. `approval`: ready-to-send ERC-20 approval tx data
2. `typedData`: populated EIP-712 payload
3. `signing`: `eth_signTypedData_v4` ready params
4. `submit`: ready-to-send create-order request shape for `POST /orders/new`
5. `query`: ready-to-use base info for `GET /orders`
