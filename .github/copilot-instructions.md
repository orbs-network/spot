# Spot DeFi Protocol - Limit Orders, TWAP, Stop-Loss

Spot is a Foundry-based Solidity project implementing a DeFi protocol for limit orders, TWAP (Time-Weighted Average Price), and stop-loss functionality on Ethereum and L2s.

## Working Effectively

### Bootstrap and Build Process
1. **Initialize Dependencies**: `git submodule update --init --recursive`
2. **Install Foundry**: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
3. **Build**: `forge build` (Compiles with 0.8.20 and 1M runs)
4. **Test**: `forge test`
5. **Format Code**: `forge fmt` (Always run before committing)

## Validation Scenarios

`forge fmt && forge test`
Always run the complete validation sequence after any changes.

## Project Architecture

### Core Components
- **OrderReactor** (`src/OrderReactor.sol`): Order validation, epoch checking, min-out computation, and settlement.
- **RePermit** (`src/RePermit.sol`): Permit2-style EIP-712 signatures tying witness data to order hashes.
- **Executor** (`src/Executor.sol`): Whitelisted fillers running Multicall venue logic and handling surplus.
- **WM** (`src/ops/WM.sol`): Allowlist management for executors and admin functions.
- **Refinery** (`src/ops/Refinery.sol`): Utility for batching multicalls and sweeping balances by basis points.
- **Cosigner** (`src/ops/Cosigner.sol`): Attests to trigger and market prices.

### Key Libraries (`src/lib/`)
- **OrderLib.sol**: Core order structure and validation.
- **EpochLib.sol**: Time-bucket controls for TWAP cadence.
- **CosignatureLib.sol**: Price attestation verification.
- **ResolutionLib.sol**: Order resolution and slippage computation.
- **OrderValidationLib.sol**: Order validation including chainid checks.
- **SettlementLib.sol**: Settlement logic for order execution.

### Critical Security Boundaries
- Executors must be allowlisted via WM.
- Orders require cosigned prices within freshness windows.
- Epoch controls prevent duplicate/early fills.
- Slippage caps protect against extreme price movements (max 50%).
- RePermit ties spending allowances to exact order hashes.
- Chain ID validation prevents cross-chain replay attacks.

## Recent Major Changes
- **Chain ID Validation**: Order and Cosignature structs now include `chainid` for cross-chain replay protection. Skeleton JSONs updated.

## Build Configuration
- **Solidity Version**: 0.8.20 (EXACT - do not change)
- **Optimization**: 1,000,000 runs
- **Remappings**: See `remappings.txt`

## Testing Strategy
- `test/base/BaseTest.sol`: Test utilities and helpers.
- `test/Executor.t.sol`: End-to-end execution.
- `test/OrderValidationLib.t.sol`: Order field validation.
- `test/RePermit.t.sol`: Signature management.
- `test/CosignatureLib.t.sol`: Cosignature and chain ID verification.
- `test/SettlementLib.t.sol`: Settlement logic.

## Deployment Scripts (`script/`)
1. `00_DeployWM.s.sol`: WM (Allowlist)
2. `01_UpdateWMWhitelist.s.sol`: Whitelist Updates
3. `02_DeployRepermit.s.sol`: RePermit
4. `03_DeployReactor.s.sol`: OrderReactor
5. `04_DeployExecutor.s.sol`: Executor

Deployments use CREATE2 for deterministic addresses across chains.

## Multi-Chain Support
Configured via `script/input/config.json`. The protocol deploys on 18+ chains.

## Repository Structure
```
├── src/
│   ├── adapter/         # Exchange adapters
│   ├── interface/       # Contract interfaces
│   ├── lib/             # Core validation, epoch, settlement, and utility libraries
│   ├── ops/             # Operations (WM, Refinery, Cosigner)
│   ├── Constants.sol    # Protocol constants
│   ├── Executor.sol     # Swap execution and callbacks
│   ├── OrderReactor.sol # Order validation and settlement
│   ├── RePermit.sol     # EIP-712 permit system
│   └── Structs.sol      # Core data structures with chainid support
├── test/                # Comprehensive test suites
├── script/              # Deployment scripts
├── lib/                 # Submodule dependencies
└── foundry.toml         # Build configuration
```