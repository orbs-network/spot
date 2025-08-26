# Spot DeFi Protocol - Limit Orders, TWAP, Stop-Loss

Spot is a Foundry-based Solidity project implementing a DeFi protocol for limit orders, TWAP (Time-Weighted Average Price), and stop-loss functionality on Ethereum and L2s.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Environment Setup - CRITICAL NETWORK LIMITATIONS
- **WARNING**: Standard Foundry installation methods are blocked in many environments due to network restrictions
- Primary installation domains (foundry.paradigm.xyz, GitHub releases, crates.io) may be inaccessible
- **ALWAYS** use the alternative installation method below

### Bootstrap and Build Process
1. **Initialize Dependencies**:
   ```bash
   git submodule update --init --recursive
   ```
   - NEVER CANCEL: This takes 3-5 minutes. Set timeout to 10+ minutes.

2. **Install Foundry** (Network-Restricted Environment):
   ```bash
   mkdir -p /home/runner/.config/.foundry/bin
   wget -q -O foundryup https://raw.githubusercontent.com/foundry-rs/foundry/master/foundryup/foundryup
   chmod +x foundryup
   ./foundryup
   export PATH="/home/runner/.config/.foundry/bin:$PATH"
   ```
   - If foundryup fails, install Solidity compiler directly:
   ```bash
   curl -L https://github.com/ethereum/solidity/releases/download/v0.8.20/solc-static-linux -o /tmp/solc && chmod +x /tmp/solc
   export FOUNDRY_SOLC=/tmp/solc
   ```

3. **Build the Project**:
   ```bash
   export PATH="/home/runner/.config/.foundry/bin:$PATH"
   forge build src/WM.sol src/Refinery.sol  # Build working contracts first
   ```
   - NEVER CANCEL: Build takes 1-2 minutes for core contracts. Set timeout to 5+ minutes.
   - **CRITICAL**: Full `forge build` currently fails due to OrderReactor compilation issues
   - **Known Issues**: 
     - OrderReactor has state mutability conflicts with UniswapX BaseReactor
     - Some test dependencies have path conflicts with ERC20Mock location
   - **Workaround**: Build individual working contracts until issues are resolved

4. **Validate Compilation**:
   ```bash
   forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol  # Working contracts
   ```
   - These core contracts compile successfully and take ~500ms
   - **DO NOT** attempt `forge test` until compilation issues are resolved
   - Focus on individual contract validation

### Alternative Build Validation
If Foundry installation completely fails:
```bash
# Use direct solc compilation for validation
/tmp/solc --version
/tmp/solc src/WM.sol --base-path . --include-path lib/UniswapX/lib/openzeppelin-contracts "@openzeppelin/contracts/=lib/UniswapX/lib/openzeppelin-contracts/contracts/"
```

## Validation Scenarios

### ALWAYS Test These Core Workflows After Changes:

1. **Basic Compilation Test**:
   ```bash
   forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol  # Should complete in ~500ms
   ```

2. **Individual Contract Validation**:
   ```bash
   forge fmt  # Format check - should complete in ~100ms
   ```

3. **Contract Interface Check**:
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
forge fmt                                           # Format code (~100ms)
forge build src/WM.sol src/Refinery.sol            # Verify working contracts compile (~500ms)
forge build src/repermit/RePermit.sol               # Test RePermit compilation (~600ms)

# Commands currently blocked by compilation issues:
# forge build                                      # Full build fails due to OrderReactor issues
# forge test                                       # Tests fail due to compilation issues  
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
- **Network Errors**: Use alternative installation methods above
- **Test Failures**: Run individual contract tests to isolate issues
- **Gas Issues**: Check .gas-snapshot for unexpected increases

## Known Issues & Workarounds
- **CRITICAL COMPILATION ISSUE**: OrderReactor has state mutability conflicts with UniswapX BaseReactor
  - Error: "Overriding function changes state mutability from 'view' to 'nonpayable'"
  - **Workaround**: Build individual contracts until this is resolved
- **Test Dependencies**: ERC20Mock path conflicts prevent full test suite from running
  - **Workaround**: Focus on individual contract testing and compilation validation
- **Network Restrictions**: Standard Foundry installation may fail - use alternative methods
- **Build Limitations**: Use `forge build src/WM.sol src/Refinery.sol src/repermit/RePermit.sol` for working compilation
- **Gas Snapshots**: Cannot run until compilation issues are resolved
- **Full Test Suite**: Currently blocked by compilation issues

**DEVELOPMENT PRIORITY**: Fix OrderReactor state mutability issue before proceeding with full development workflow.

**NEVER** ignore compilation errors or test failures - they often indicate critical security issues in a DeFi protocol handling user funds.