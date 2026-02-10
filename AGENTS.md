# AGENTS.md

## Adapter Routing Design 🚧
- Goal: enable flexible adapter routing at fill time

### DelegatingAdapter 🔁
- Purpose: route to another adapter at fill time via `delegatecall`
- Encoding: `Execution.data` encodes `(adapter, adapterData)`
- Flow: Executor `delegatecall`s DelegatingAdapter then it `delegatecall`s the chosen adapter
- Context: adapter logic runs in Executor storage so it must be stateless; use immutables or external registries
- Trust: without checks the executor chooses any adapter per fill

### UniversalAdapter 🌐
- Purpose: route to any target contract via `call` (not `delegatecall`)
- Encoding: `Execution.data` encodes `(target, callData)`
- Flow: Executor `delegatecall`s UniversalAdapter then it `call`s the target
- Token flow: approve input token to target then call then reset approvals
- Context: target sees `msg.sender` as Executor, so routers pull from Executor

### Adapter(0) vs DelegatingAdapter ⚖️
- Adapter(0) implies execution selects adapter and it requires core and ABI changes
- DelegatingAdapter keeps the order bound to a policy address and avoids ABI changes
- Trust model is equivalent if DelegatingAdapter has no policy checks
- DelegatingAdapter can add policy checks later without changing order format

## External Liquidity Design 🚧
- Add adapter `Settler` for solver EOA liquidity
- Keep `OrderReactor` unchanged

### Data And Signing 🧾
- `Execution.data` encodes `outputAmount` and `solverSig`
- Solver signs a RePermit witness over `OrderLib.hash(order)` with `OrderLib.WITNESS_TYPE_SUFFIX`
- Permit uses output token and `outputAmount` plus order nonce and deadline
- Spender in the witness is the executor address

### Settler Adapter Behavior ⚙️
- Decode `outputAmount` and `solverSig`
- Build the RePermit struct and digest
- Recover solver EOA and check allowlist if enabled
- Call `repermitWitnessTransferFrom` to pull output into the executor
- Transfer input token from executor to solver
- Do not add explicit output amount checks and rely on `SettlementLib.guard`

### Assumptions And Limits ⚠️
- Output token can be ERC20 or native
- Settler auto-wraps and unwraps native output as needed
- `outputAmount` should include output token fees
- Solver validates order fields and adapter choice offchain

