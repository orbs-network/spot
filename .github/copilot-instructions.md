# Spot DeFi Protocol - Limit Orders, TWAP, Stop-Loss

Spot is a Foundry-based Solidity project implementing a DeFi protocol for limit orders, TWAP (Time-Weighted Average Price), and stop-loss functionality on Ethereum and L2s.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Environment Setup
Standard Foundry installation now works normally without network restrictions.

### Bootstrap and Build Process
1. **Initialize Dependencies**:
   ```bash
   git submodule update --init --recursive
   ```
   - NEVER CANCEL: This takes 6-7 seconds. Set timeout to 10+ minutes.

2. **Install Foundry**:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   source ~/.bashrc
   foundryup
   ```
   - Standard installation takes ~30 seconds
   - Installs forge, cast, anvil, and chisel
   - Verifies binaries against attestation files

3. **Build the Project**:
   ```bash
   source ~/.bashrc  # Required in new shell sessions
   forge build
   ```
   - Takes ~10 seconds with 1M optimization runs
   - Compiles 87 Solidity files with 0.8.20
   - NEVER CANCEL: Set timeout to 60+ seconds minimum

4. **Run Tests**:
   ```bash
   forge test
   ```
   - Takes <1 second (100 tests across 13 suites)
   - All tests should pass in fresh environment
   - NEVER CANCEL: Set timeout to 30+ seconds

5. **Format Code**:
   ```bash
   forge fmt
   ```
   - Takes <0.1 seconds
   - Always run before committing changes

## Validation Scenarios

`forge fmt; forge test`

After making any changes to the codebase, always run the complete validation sequence:

1. **Format and Test**:
   ```bash
   forge fmt && forge test
   ```

2. **Gas Snapshot Validation** (optional):
   ```bash
   forge snapshot --check
   ```
   - Gas values may differ across environments
   - Only check for major regressions, not minor differences

## Project Architecture

### Core Components
- **OrderReactor** (`src/reactor/`): Order validation, epoch checking, min-out computation from cosigned prices, settlement
- **RePermit** (`src/repermit/`): Permit2-style EIP-712 signatures with witness data tied to order hashes  
- **Executor** (`src/executor/`): Whitelisted fillers that run Multicall venue logic and handle surplus
- **WM** (`src/WM.sol`): Allowlist management for executors and admin functions
- **Refinery** (`src/Refinery.sol`): Operations utility for batching and sweeping balances by basis points

### Key Libraries
- **OrderLib** (`src/reactor/OrderLib.sol`): Core order structure and validation
- **EpochLib** (`src/reactor/EpochLib.sol`): Time-bucket controls for TWAP cadence
- **CosignatureLib** (`src/reactor/CosignatureLib.sol`): Price attestation verification
- **ResolutionLib** (`src/reactor/ResolutionLib.sol`): Order resolution and slippage computation

### Critical Security Boundaries
- All executors must be allowlisted via WM
- Orders require cosigned prices within freshness windows
- Epoch controls prevent duplicate/early fills
- Slippage caps protect against extreme price movements (max 50%)
- RePermit ties spending allowances to exact order hashes

## Build Configuration
- **Solidity Version**: 0.8.20 (EXACT - do not change)
- **Optimization**: 1,000,000 runs for maximum gas efficiency
- **Dependencies**: Managed via git submodules (UniswapX, OpenZeppelin, Solmate, forge-std)
- **Remappings**: See `remappings.txt` - critical for compilation

## Testing Strategy
The project has comprehensive test coverage across all components:

- **Unit Tests**: Individual library and component validation
- **Integration Tests**: End-to-end order execution flows  
- **Fuzz Tests**: Property-based testing for edge cases
- **Gas Tests**: Consumption tracking via `.gas-snapshot`

Key test files to understand:
- `test/base/BaseTest.sol`: Common test utilities and helpers
- `test/executor/Executor.t.sol`: End-to-end order execution
- `test/reactor/OrderValidationLib.t.sol`: Order validation logic
- `test/RePermit.t.sol`: Signature and allowance management

## Deployment Process
1. **WM (Allowlist)**: `script/00_DeployWM.s.sol`
2. **Whitelist Updates**: `script/01_UpdateWMWhitelist.s.sol`
3. **RePermit**: `script/02_DeployRepermit.s.sol` 
4. **OrderReactor**: `script/03_DeployReactor.s.sol`
5. **Executor**: `script/04_DeployExecutor.s.sol`

All deployments use CREATE2 with configurable salts for deterministic addresses across chains.

## Multi-Chain Support
The protocol deploys on 18+ chains. Key considerations:
- Deployment addresses are deterministic via CREATE2
- Configuration stored in `script/input/config.json`
- Chain-specific admin addresses and fee collectors
- Consistent contract bytecode across all chains

## Common Tasks

### Repository Structure
```
├── src/
│   ├── reactor/         # Order validation and settlement
│   ├── repermit/        # EIP-712 permit system
│   ├── executor/        # Swap execution and callbacks
│   ├── adapter/         # Exchange adapters
│   ├── interface/       # Contract interfaces
│   ├── WM.sol          # Allowlist management
│   └── Refinery.sol    # Operations utilities
├── test/               # Comprehensive test suites
├── script/             # Deployment scripts
├── lib/                # Git submodule dependencies
└── foundry.toml        # Build configuration
```

### Key Files Reference
- `foundry.toml`: Build configuration (0.8.20, 1M runs)
- `remappings.txt`: Import path mappings
- `.gas-snapshot`: Gas consumption baselines
- `script/input/config.json`: Multi-chain deployment config

## Debugging Tips
- **Build Failures**: Check submodule initialization first
- **Path Issues**: Verify remappings.txt matches dependency structure  
- **Gas Issues**: Check .gas-snapshot for unexpected increases (when available)

**NEVER** ignore compilation errors or test failures - they often indicate critical security issues in a DeFi protocol handling user funds.