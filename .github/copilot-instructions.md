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

3. **Build Working Contracts**:
   ```bash
   forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol
   ```
   - **Timing**: ~0.8 seconds for working contracts
   - **CRITICAL**: Full `forge build` still fails due to compilation issues
   - **Known Issues**: 
     - OrderReactor has state mutability conflicts with UniswapX BaseReactor
     - Test dependencies have ERC20Mock path resolution issues
   - **Workaround**: Build individual working contracts until issues are resolved

## Validation Scenarios

### ALWAYS Test These Core Workflows After Changes:

1. **Basic Compilation Test**:
   ```bash
   forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol  # Should complete in ~0.8s
   ```

2. **Code Formatting Check**:
   ```bash
   forge fmt --check  # Format validation - should complete in ~0.1s
   ```

3. **Individual Contract Validation**:
   ```bash
   forge build src/WM.sol  # Test allowlist contract compilation
   ```

4. **Multi-Chain Configuration Validation**:
   - Check `script/input/config.json` for deployment addresses
   - Verify chain IDs and contract addresses are consistent

5. **Deployment Script Syntax Check**:
   ```bash
   forge script script/00_DeployWM.s.sol --help  # Verify script syntax
   ```
   - **Note**: Actual deployment testing requires fixing compilation issues first

### Manual Validation Requirements
- **ALWAYS** validate that changes maintain the allowlist security model
- Test that RePermit signatures are properly validated
- Verify that OrderReactor properly handles epoch and slippage calculations
- Check that Executor correctly manages surplus distribution
- Ensure WM (allowlist) controls are not bypassed

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

## Common Validation Commands
```bash
# Working commands - always run these before committing changes
forge fmt --check                                   # Format validation (~0.1s)
forge build src/WM.sol src/Refinery.sol             # Verify working contracts compile (~0.8s)
forge build src/repermit/RePermit.sol               # Test RePermit compilation (~0.8s)

# Commands currently blocked by compilation issues:
# forge build                                      # Full build fails due to OrderReactor state mutability issues
# forge test                                       # Tests fail due to ERC20Mock path resolution issues
# forge snapshot                                   # Gas snapshots unavailable until build works
```

## Deployment Process
1. **WM (Allowlist)**: `script/00_DeployWM.s.sol`
2. **RePermit**: `script/02_DeployRepermit.s.sol` 
3. **OrderReactor**: `script/03_DeployReactor.s.sol`
4. **Executor**: `script/04_DeployExecutor.s.sol`
5. **Whitelist Updates**: `script/01_UpdateWMWhitelist.s.sol`

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
- **State Mutability Errors**: Known issue with OrderReactor inheritance from UniswapX BaseReactor
- **Test Failures**: ERC20Mock path resolution issues prevent test compilation
- **Gas Issues**: Check .gas-snapshot for unexpected increases (when available)

## Known Issues & Workarounds
- **CRITICAL COMPILATION ISSUE**: OrderReactor has state mutability conflicts with UniswapX BaseReactor
  - Error: "Overriding function changes state mutability from 'view' to 'nonpayable'"
  - Location: `src/reactor/OrderReactor.sol:34` overriding `lib/UniswapX/src/reactors/BaseReactor.sol:139`
  - **Workaround**: Build individual contracts until this is resolved
- **Test Dependencies**: ERC20Mock path resolution issues prevent full test suite from running
  - Error: Source "lib/UniswapX/lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol" not found
  - **Workaround**: Focus on individual contract testing and compilation validation
- **Build Limitations**: Use `forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol` for working compilation
- **Gas Snapshots**: Cannot run until compilation issues are resolved
- **Full Test Suite**: Currently blocked by compilation issues

**DEVELOPMENT PRIORITY**: Fix OrderReactor state mutability issue before proceeding with full development workflow.

**NEVER** ignore compilation errors or test failures - they often indicate critical security issues in a DeFi protocol handling user funds.