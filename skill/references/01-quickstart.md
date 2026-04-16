# Quickstart

1. Required fields: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. Choose the intended order shape before populating JSON: market, limit, stop-loss, take-profit, delayed-start, or chunked/TWAP. Shapes can be mixed in one order.
3. Build and normalize a params JSON object using [02-params.md](02-params.md).
4. Fill the remaining `<...>` placeholders in [../assets/repermit.template.json](../assets/repermit.template.json), leaving the fixed template fields unchanged.
5. If approval is needed, follow [03-sign.md](03-sign.md).
6. Sign `typedData` as the `swapper`.
7. Submit, query, or cancel according to [03-sign.md](03-sign.md), depending on the requested task.
8. Use [04-examples.md](04-examples.md) only if you still need a full mock relay payload as a reference.
