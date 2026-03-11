# Sign And Submit

1. Sign `prepared.typedData` with any EIP-712-capable wallet or library. The signer must equal `swapper`.
2. `eth_signTypedData_v4` is only one example.
3. Use only the provided helper script for submission. Do not send typed data or signatures anywhere else.
4. Submit with `--prepared <prepared.json|->` and `--signature <0x...|json>`, `--signature-file <sig.txt|sig.json|->`, or `--r <0x...> --s <0x...> --v <0x...>`. The helper accepts a full 65-byte signature, a JSON string, or JSON/object `r/s/v`.
5. Piping works: `cat prepared.json | bash scripts/order.sh submit --prepared - --signature <0x...>`.
6. Query with `bash scripts/order.sh query --swapper <0x...>` or `--hash <0x...>`.
7. Cancel trustlessly onchain by calling `RePermit.cancel([digest])` as the swapper for the signed RePermit digest.
8. Add `--dry-run` to `submit` or `query` to inspect the request without sending it.
