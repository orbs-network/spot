# Spot API

Institutional integration for gasless, non-custodial market, limit, TWAP, stop-loss, take-profit, and delayed-start orders.

## 🧩 Model

1. Build orders locally from the canonical [skill](skill/SKILL.md).
2. Approve the RePermit contract onchain when required.
3. Sign EIP-712 client-side; never send private keys.
4. Submit only the signed order to the relay.
5. Monitor by order hash; cancel exact orders onchain.

## 🎯 Endpoints

1. `POST https://agents-sink.orbs.network/orders/new` — submit.
2. `GET https://agents-sink.orbs.network/orders?hash=<orderHash>` — query.
3. `GET https://agents-sink.orbs.network/orders?swapper=<address>` — recover a missing hash.

## 🛠️ Create

1. Normalize intent with [params](skill/references/params.md).
2. Replace only placeholders in the [typed-data template](skill/assets/repermit.template.json); preserve fixed fields.
3. Approve `typedData.domain.verifyingContract` for `input.maxAmount` if allowance is insufficient.
4. Sign `typedData` as `swapper`.
5. Submit:

```json
{
  "order": "<typedData.message>",
  "signature": "<full signature>",
  "status": "pending"
}
```

`signature` may instead be the exact `{ "r": "...", "s": "...", "v": "..." }` object returned by the signer.

```sh
curl -fsS -X POST 'https://agents-sink.orbs.network/orders/new' \
  -H 'content-type: application/json' \
  --data @relay-payload.json
```

Persist the exact populated typed data and signature. Reuse both after an ambiguous timeout or `5xx`.

## 🧬 Order profiles

1. Market: `output.limit = 0`.
2. Limit: `output.limit > 0`.
3. Stop-loss: `output.triggerLower > 0`.
4. Take-profit: `output.triggerUpper > 0`.
5. TWAP: `input.amount < input.maxAmount`, `epoch >= 60`.
6. Delayed: future `start`.

Profiles may be combined. Amounts use token smallest units; output controls are per chunk.

## 📡 Monitor

```sh
curl -fsS 'https://agents-sink.orbs.network/orders?hash=<orderHash>'
```

Read `.orders[0].metadata.status`, falling back to `.orders[0].status`. Poll every 5 seconds while `pending` or `eligible`; terminal states are defined in [lifecycle](skill/references/lifecycle.md).

## ❌ Cancel

1. Derive the EIP-712 digest from the exact submitted typed data.
2. From `swapper`, call `cancel(bytes32[] digests)` on `typedData.domain.verifyingContract`.
3. Wait for confirmation, then poll the relay to a terminal state.

## 🔒 Controls

1. Keep signing and key custody inside institutional infrastructure.
2. Validate the chain against [supported chains](skill/SKILL.md#supported-chains).
3. Use exact approval by default; opt into `maxUint256` only for repeat-order policy.
4. Treat `output.recipient != swapper` as a high-risk override.
5. Keep large integers as decimal strings and addresses as `0x` strings.

## 📖 Canonical reference

1. [Quickstart](skill/references/quickstart.md)
2. [Parameters and validation](skill/references/params.md)
3. [Approval, signing, and submission](skill/references/sign.md)
4. [Query and cancellation](skill/references/lifecycle.md)
5. [Full payload examples](skill/references/examples.md)
