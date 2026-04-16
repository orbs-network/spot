# Template, Sign, And Send

1. Load [../assets/repermit.template.json](../assets/repermit.template.json) and the normalized params. Respect the JSON typing rules from [02-params.md](02-params.md).
2. Replace only the remaining `<...>` placeholders. Keep the fixed protocol fields already present in the template unchanged. Set `<ADAPTER>` to the adapter listed for `chainId` in the generated `## Config` JSON block in [../SKILL.md](../SKILL.md).
3. If allowance for `input.token` to `typedData.domain.verifyingContract` is lower than `input.maxAmount`, the default suggestion is a standard ERC-20 `approve(typedData.domain.verifyingContract, input.maxAmount)` transaction first.
4. If you explicitly want a standing approval instead, `maxUint256` is often more convenient for repeat orders, but keep it opt-in rather than the default suggestion.
5. Sign `typedData` with any EIP-712-capable wallet or library. The signer must equal `swapper`.
6. Submit this exact relay payload to `https://agents-sink.orbs.network/orders/new`:

```json
{
  "order": "<typedData.message>",
  "signature": "<full signature or { r, s, v }>",
  "status": "pending"
}
```

7. Relay accepts either one full signature hex string or the exact `{ "r": "...", "s": "...", "v": "..." }` object returned by the signer.
8. Send the signature exactly as returned. Do not split, normalize, or rewrite it.
9. Query submitted orders with `GET https://agents-sink.orbs.network/orders?hash=<orderHash>`. If you do not have `orderHash`, `GET https://agents-sink.orbs.network/orders?swapper=<swapper>` also works.
10. To cancel an order, compute the EIP-712 digest of the same populated `typedData` and call `cancel(bytes32[] digests)` on `typedData.domain.verifyingContract` from `swapper` with `[digest]`.
11. Cancellation is exact-match and onchain. It invalidates only that digest, not every order by the same `swapper`.
12. See [04-examples.md](04-examples.md) for full payload examples.
