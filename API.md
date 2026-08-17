# Spot API

Gasless, non-custodial market, limit, TWAP, stop-loss, take-profit, and delayed-start orders on EVM chains.

## 🎯 Endpoints

1. `POST https://agents-sink.orbs.network/orders/new` — submit a signed order.
2. `GET https://agents-sink.orbs.network/orders?hash=<orderHash>` — query one order.
3. `GET https://agents-sink.orbs.network/orders?swapper=<address>` — recover a missing hash.

No private key or API key is sent to the relay. Signing stays client-side.

## 🌐 Networks

Supported chain IDs: `1`, `10`, `14`, `56`, `130`, `137`, `143`, `146`, `196`, `999`, `1329`, `4326`, `8453`, `42161`, `43114`, `59144`, `80094`, `747474`.

## 🧩 Order fields

1. Required: `chainId`, `swapper`, `input.token`, `input.amount`, `output.token`.
2. `input.amount`: amount per fill, in input-token units.
3. `input.maxAmount`: total amount, default `input.amount`; round down to whole chunks.
4. `output.limit`, `triggerLower`, `triggerUpper`: per-fill output-token units.
5. Market: `limit = 0`; limit: `limit > 0`.
6. Stop-loss: `triggerLower > 0`; take-profit: `triggerUpper > 0`.
7. TWAP: `input.amount < input.maxAmount` and `epoch >= 60`.
8. Delayed start: future `start`.
9. Native input is unsupported; wrap it first. Native output uses `0x0000000000000000000000000000000000000000`.

Profiles may be combined.

## ⚙️ Defaults

1. `nonce = now`, `start = now` in Unix seconds, `recipient = swapper`.
2. `maxAmount = amount`.
3. `epoch = 0`, or `60` for TWAP.
4. `freshness = 50`, `slippage = 500` basis points.
5. `deadline = start + 300 + chunkCount * epoch`, where `chunkCount = maxAmount / amount`.
6. `limit = triggerLower = triggerUpper = 0`.

Validate `start != 0`, `amount > 0`, `amount <= maxAmount`, different input/output tokens, `triggerLower <= triggerUpper` when the upper trigger is set, `slippage <= 5000`, `freshness > 0`, and `freshness < epoch` when `epoch > 0`.

## ✍️ Sign

Use these fixed protocol values on every supported chain:

```js
const REP = "0x00002a9C4D9497df5Bd31768eC5d30eEf5405000";
const REACTOR = "0x000000b33fE4fB9d999Dd684F79b110731c3d000";
const EXECUTOR = "0x000642A0966d9bd49870D9519f76b5cf823f3000";
const ADAPTER = "0x0002BeFB46587d460AcEA9B2792c4A4c67B9cADa";
const ZERO = "0x0000000000000000000000000000000000000000";

const domain = {
  name: "RePermit",
  version: "1",
  chainId,
  verifyingContract: REP,
};

const types = {
  TokenPermissions: [
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
  ],
  Exchange: [
    { name: "adapter", type: "address" },
    { name: "ref", type: "address" },
    { name: "share", type: "uint32" },
    { name: "data", type: "bytes" },
  ],
  Input: [
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "maxAmount", type: "uint256" },
  ],
  Output: [
    { name: "token", type: "address" },
    { name: "limit", type: "uint256" },
    { name: "triggerLower", type: "uint256" },
    { name: "triggerUpper", type: "uint256" },
    { name: "recipient", type: "address" },
  ],
  Order: [
    { name: "reactor", type: "address" },
    { name: "executor", type: "address" },
    { name: "exchange", type: "Exchange" },
    { name: "swapper", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "start", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "chainid", type: "uint256" },
    { name: "exclusivity", type: "uint32" },
    { name: "epoch", type: "uint32" },
    { name: "slippage", type: "uint32" },
    { name: "freshness", type: "uint32" },
    { name: "input", type: "Input" },
    { name: "output", type: "Output" },
  ],
  RePermitWitnessTransferFrom: [
    { name: "permitted", type: "TokenPermissions" },
    { name: "spender", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "witness", type: "Order" },
  ],
};

const message = {
  permitted: { token: inputToken, amount: maxAmount },
  spender: REACTOR,
  nonce,
  deadline,
  witness: {
    reactor: REACTOR,
    executor: EXECUTOR,
    exchange: { adapter: ADAPTER, ref: ZERO, share: 0, data: "0x" },
    swapper,
    nonce,
    start,
    deadline,
    chainid: chainId,
    exclusivity: 0,
    epoch,
    slippage,
    freshness,
    input: { token: inputToken, amount, maxAmount },
    output: { token: outputToken, limit, triggerLower, triggerUpper, recipient: swapper },
  },
};

const signature = await signer.signTypedData(domain, types, message);
```

Large integers should be decimal strings. The signer address must equal `swapper`.

## 🔐 Approve

Before signing, ensure `input.token` allowance to `REP` is at least `maxAmount`. Default to `approve(REP, maxAmount)`; use `maxUint256` only under an explicit standing-approval policy.

## 📤 Submit

```js
const response = await fetch("https://agents-sink.orbs.network/orders/new", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ order: message, signature, status: "pending" }),
});

const body = await response.json();
const orderHash = body.orderHash ?? body.signedOrder?.hash;
```

The relay also accepts the exact `{ r, s, v }` signature object returned by a signer. Persist `domain`, `types`, `message`, and `signature`; reuse them unchanged after a timeout or `5xx`.

## 📡 Monitor

Read `.orders[0].metadata.status`, falling back to `.orders[0].status`. Poll every 5 seconds while `pending` or `eligible`.

Terminal statuses: `filled`, `completed`, `partially_completed`, `cancelled`, `expired`, `failed`, `rejected`.

## ❌ Cancel

```js
import { Contract, TypedDataEncoder } from "ethers";

const digest = TypedDataEncoder.hash(domain, types, message);
const repermit = new Contract(REP, ["function cancel(bytes32[] digests)"], signer);
await (await repermit.cancel([digest])).wait();
```

Cancellation is exact-match and onchain. After confirmation, poll until the relay reports a terminal status.

## 🔒 Safety

1. Never send private keys to the relay.
2. Preserve fixed protocol addresses and fields exactly.
3. Treat `recipient != swapper` as a high-risk override.
4. Keep the exact signed payload for retries, audits, and cancellation.
