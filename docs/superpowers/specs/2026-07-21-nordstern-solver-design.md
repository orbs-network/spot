# Nordstern Solver Deployment Design

## Scope

Add Nordstern as a solver on every chain supported by both Spot and Nordstern's live chain registry. The current intersection contains 18 chains: Ethereum, Optimism, Flare, BNB Chain, Unichain, Polygon, Monad, Sonic, Manta Pacific, HyperEVM, Sei, Mantle, Base, Arbitrum One, Avalanche, Linea, Berachain, and Katana.

X Layer, Moonbeam, and MegaETH remain unchanged because Nordstern's live registry does not list them.

## Adapter

Use `DefaultDexAdapter` with Nordstern's router for each chain. Nordstern's API documentation requires callers to approve the returned router directly, with no Permit2 or separate transfer proxy. The adapter pins execution to that router, grants only the order input amount, executes Nordstern's calldata, and clears the allowance afterward.

No new Solidity contract or fee contract is required.

## Configuration

After successful deployment, add one `Nordstern` entry to each selected chain's `adapter` map in `config.json`. Keep Nordstern router metadata as deployment input from the live registry; do not add a full `dex.nordstern` integration because the requested surface is solver support only.

Run the repository build after each repository change so derived skill metadata remains synchronized.

## Deployment Flow

1. Fetch Nordstern's live chain registry and validate the selected chain IDs and router addresses.
2. Confirm each router has bytecode on its chain.
3. Confirm the active signer, deployment target, CREATE2 salt, expected adapter address, balance, and gas estimate without exposing secrets.
4. Run one `DeployDefaultAdapter` broadcast per chain concurrently, with isolated output logs and no concurrent writes to `config.json`.
5. Require a successful receipt and deployed bytecode for every chain.
6. Merge all returned adapter addresses into `config.json` in one atomic edit.

The deployment salt is `keccak256("Nordstern")`, matching the existing solver adapter convention.

## Failure Handling

Treat each chain as an independent deployment branch. Preserve every transaction hash and log. Do not update `config.json` for a chain unless its deployment succeeded and bytecode exists at the returned address. Retry only when the original transaction state is unambiguous; never replace a pending transaction blindly.

If any chain fails, report that chain and retain successful onchain deployments, but do not claim the 18-chain rollout complete.

## Verification

Before deployment, run focused configuration/deployment checks and `npm run build`. After deployment and the config edit, run `npm run build`, the full test suite, config validation, and per-chain bytecode plus immutable-router checks. The final report includes each chain, router, adapter address, transaction hash, and receipt status.
