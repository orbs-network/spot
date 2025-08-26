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
   - NEVER CANCEL: This takes 3-5 minutes. Set timeout to 10+ minutes.

2. **Install Foundry**:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   source ~/.bashrc
   foundryup
   ```
   - Standard installation takes ~30 seconds
   - Installs forge, cast, anvil, and chisel
   - Verifies binaries against attestation files



## Validation Scenarios

`forge fmt; forge test`



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

## Debugging Tips
- **Build Failures**: Check submodule initialization first
- **Path Issues**: Verify remappings.txt matches dependency structure  
- **Gas Issues**: Check .gas-snapshot for unexpected increases (when available)

**NEVER** ignore compilation errors or test failures - they often indicate critical security issues in a DeFi protocol handling user funds.