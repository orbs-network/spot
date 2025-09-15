# Spot — Limit, TWAP, Stop-Loss DeFi Protocol

**A Solidity protocol for noncustodial advanced order types on EVM chains.**

## Who It's For

- 🧭 **Product**: Ship price-target, time-sliced, and protective orders with professional-grade execution
- 🤝 **Business Development**: Onboard MMs/venues with transparent rev-share and attribution mechanisms
- 🧩 **Integrators**: Drop-in EIP-712 orders, cosigned prices, and modular executor architecture
- 🔧 **Developers**: Clean, well-tested Solidity codebase with comprehensive tooling

## What It Does

- 🎯 **Limit Orders**: Execute at or above a target output amount with oracle price protection
- ⏱️ **TWAP Orders**: Slice total size into fixed "chunks" per configurable epoch intervals
- 🛡️ **Stop-Loss/Take-Profit**: Execute only when cosigned price breaches trigger boundaries
- 🔄 **Composable Execution**: Mix and match the above order types with custom exchange adapters

## Why It Wins

- ✅ **Non-custodial**: Per-order allowances via RePermit with witness-bound spending authorization
- 🔒 **Battle-tested Security**: Cosigned prices, slippage caps (max 49.99%), deadlines, and epoch gating
- ⚙️ **Modular Architecture**: Inlined reactor settlement + pluggable executor strategies
- 📈 **Built-in Revenue**: Configurable referral shares and automatic surplus distribution
- 🏗️ **Production Ready**: 1M optimization runs, comprehensive test coverage, multi-chain deployments

## Architecture

### Core Components

- 🧠 **OrderReactor** (`src/reactor/OrderReactor.sol`): Validates orders, checks epoch constraints, computes minimum output from cosigned prices, and settles via inlined implementation with reentrancy protection
- ✍️ **RePermit** (`src/repermit/RePermit.sol`): Permit2-style EIP-712 signatures with witness data that binds spending allowances to exact order hashes, preventing signature reuse
- 🧾 **Cosigner**: External service that signs current market prices (input/output ratios) with enforced freshness windows and proper token validation
- 🛠️ **Executor** (`src/executor/Executor.sol`): Whitelisted fillers that run venue logic via delegatecall to adapters, ensure minimum output requirements, and distribute surplus
- 🔐 **WM** (`src/WM.sol`): Two-step ownership allowlist manager for executors and admin functions with event emission
- 🏭 **Refinery** (`src/Refinery.sol`): Operations utility for batching multicalls and sweeping token balances by basis points
- 🧰 **Approvals**: Exact allowances set to reactor using `SafeERC20.forceApprove()` (USDT-safe, prevents allowance accumulation)

### Key Libraries

- **OrderLib** (`src/reactor/lib/OrderLib.sol`): EIP-712 structured data hashing for orders and cosignatures
- **OrderValidationLib** (`src/reactor/lib/OrderValidationLib.sol`): Order field validation (amounts, tokens, slippage caps)
- **ResolutionLib** (`src/reactor/lib/ResolutionLib.sol`): Price resolution logic using cosigned rates with slippage protection
- **EpochLib** (`src/reactor/lib/EpochLib.sol`): Time-bucket management for TWAP order execution intervals
- **CosignatureLib** (`src/reactor/lib/CosignatureLib.sol`): Cosigner validation and freshness checking
- **ExclusivityOverrideLib** (`src/reactor/lib/ExclusivityOverrideLib.sol`): Time-bounded exclusivity with override mechanics
- **SurplusLib** (`src/executor/lib/SurplusLib.sol`): Automatic surplus distribution between swappers and referrers
- **SettlementLib** (`src/executor/lib/SettlementLib.sol`): Token transfer coordination with gas fee handling
- **TokenLib** (`src/executor/lib/TokenLib.sol`): Safe token operations with ETH/ERC20 abstraction

## Order Structure

Based on `src/Structs.sol`, each order contains:

```solidity
struct Order {
    address reactor;           // OrderReactor contract address
    address executor;          // Authorized executor for this order
    Exchange exchange;         // Adapter, referrer, and data
    address swapper;           // Order creator/signer
    uint256 nonce;            // Unique identifier
    uint256 deadline;         // Expiration timestamp
    uint32 exclusivity;       // Time-bounded exclusive execution
    uint32 epoch;             // Seconds between fills (0 = single-use)
    uint32 slippage;          // BPS applied to cosigned price
    uint32 freshness;         // Cosignature validity window in seconds
    Input input;              // Token to spend
    Output output;            // Token to receive
}

struct Input {
    address token;            // Input token address
    uint256 amount;           // Per-fill "chunk" amount
    uint256 maxAmount;        // Total amount across all fills
}

struct Output {
    address token;            // Output token address
    uint256 amount;           // Minimum acceptable output (limit)
    uint256 maxAmount;        // Stop trigger (max uint256 = disabled)
    address recipient;        // Where to send output tokens
}
```

## Flow (Plain English)

1. **Order Creation**: User signs one EIP-712 order with chunk size, total amount, limits, slippage tolerance, epoch interval, and deadline
2. **Price Attestation**: Cosigner provides fresh market price data (input/output token ratios) with timestamp validation
3. **Execution**: Whitelisted executor calls `Executor.execute()` with order and execution parameters
4. **Validation**: OrderReactor validates signatures, checks epoch windows, applies slippage protection, and enforces limits/stops
5. **Settlement**: Reactor transfers input tokens, executor runs adapter logic via delegatecall, ensures minimum output, and settles
6. **Distribution**: Surplus tokens are automatically distributed between swapper and optional referrer based on configured shares

## Order Types & Examples

### Single-Shot Limit Order
```solidity
Order memory order = Order({
    // ... standard fields
    epoch: 0,                    // Single execution
    input: Input({
        amount: 1000e6,          // Exact amount to spend
        maxAmount: 1000e6        // Same as amount
    }),
    output: Output({
        amount: 950e18,          // Minimum acceptable output
        maxAmount: type(uint256).max  // No stop trigger
    })
});
```

### TWAP Order
```solidity
Order memory order = Order({
    // ... standard fields
    epoch: 3600,                 // Execute every hour
    input: Input({
        amount: 100e6,           // 100 USDC per chunk
        maxAmount: 1000e6        // 1000 USDC total budget
    }),
    output: Output({
        amount: 95e18,           // Minimum per chunk
        maxAmount: type(uint256).max
    })
});
```

### Stop-Loss Order
```solidity
Order memory order = Order({
    // ... standard fields
    epoch: 0,                    // Single execution
    output: Output({
        amount: 900e18,          // Minimum output
        maxAmount: 950e18        // Stop if price drops below this
    })
});
```

## Integration Guide

### 1. Set Up Development Environment

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and build
git clone https://github.com/orbs-network/spot.git
cd spot
git submodule update --init --recursive
forge build
forge test
```

### 2. Deploy Contracts

The deployment process follows a specific sequence:

```bash
# 1. Deploy WM (allowlist manager)
forge script script/00_DeployWM.s.sol

# 2. Update WM whitelist
forge script script/01_UpdateWMWhitelist.s.sol

# 3. Deploy RePermit
forge script script/02_DeployRepermit.s.sol

# 4. Deploy OrderReactor
forge script script/03_DeployReactor.s.sol

# 5. Deploy Executor
forge script script/04_DeployExecutor.s.sol
```

### 3. Implement Exchange Adapter

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

contract MyDexAdapter is IExchangeAdapter {
    function delegateSwap(
        bytes32 hash,
        uint256 resolvedAmountOut,
        CosignedOrder memory co,
        Execution memory x
    ) external override {
        // Decode your exchange-specific data
        (address router, bytes memory swapData) = abi.decode(x.data, (address, bytes));
        
        // Execute swap logic
        // Ensure sufficient output tokens are available for settlement
        require(outputToken.balanceOf(address(this)) >= resolvedAmountOut, "Insufficient output");
    }
}
```

### 4. Create and Execute Orders

```solidity
// Create cosigned order
CosignedOrder memory co = CosignedOrder({
    order: order,
    signature: userSignature,
    cosignatureData: priceData,
    cosignature: cosignerSignature
});

// Execute via whitelisted executor
Execution memory execution = Execution({
    minAmountOut: computedMinOut,
    fee: Output({...}),  // Optional gas fee
    data: abi.encode(router, swapCalldata)
});

executor.execute(co, execution);
```

## Security Model

### Access Controls
- **WM Allowlist**: Only approved executors can fill orders via `WM.allowed(address)` check
- **Two-Step Ownership**: `WM` uses OpenZeppelin's `Ownable2Step` for secure ownership transfers
- **Executor Binding**: Orders specify authorized executor; only that executor can fill the order

### Validation Layers
- **Order Validation**: `OrderValidationLib.validate()` checks all order fields for validity
- **Signature Verification**: RePermit validates EIP-712 signatures and witness data binding
- **Epoch Enforcement**: `EpochLib.update()` prevents early/duplicate fills within time windows
- **Slippage Protection**: Maximum 49.99% slippage cap enforced in `Constants.MAX_SLIPPAGE`
- **Freshness Windows**: Cosignatures expire after configurable time periods

### Economic Security
- **Witness-Bound Spending**: RePermit ties allowances to exact order hashes, preventing signature reuse
- **Surplus Distribution**: Automatic fair distribution of any excess tokens between swapper and referrer
- **Exact Allowances**: `SafeERC20.forceApprove()` prevents allowance accumulation attacks

### Operational Security
- **Reentrancy Protection**: `ReentrancyGuard` on all external entry points
- **Safe Token Handling**: Comprehensive support for USDT-like tokens and ETH
- **Delegatecall Isolation**: Adapters run in controlled executor context with proper validation

## Limits & Constants

- **Maximum Slippage**: 4,999 BPS (49.99%) - defined in `src/reactor/Constants.sol`
- **Basis Points**: 10,000 BPS = 100% - standard denomination for all percentage calculations
- **Freshness Requirements**: Must be > 0 seconds; must be < epoch duration when epoch != 0
- **Epoch Behavior**: 0 = single execution, >0 = recurring with specified interval
- **Gas Optimization**: 1,000,000 optimizer runs for maximum efficiency

## Project Structure

```
src/
├── reactor/                 # Order validation and settlement
│   ├── OrderReactor.sol    # Main reactor contract
│   ├── Constants.sol       # Protocol constants
│   └── lib/                # Supporting libraries
├── repermit/               # EIP-712 permit system
│   ├── RePermit.sol        # Main permit contract
│   └── RePermitLib.sol     # Helper functions
├── executor/               # Swap execution and callbacks
│   ├── Executor.sol        # Main executor contract
│   └── lib/                # Execution libraries
├── adapter/                # Exchange adapters
│   └── DefaultDexAdapter.sol
├── interface/              # Contract interfaces
├── Structs.sol            # Data structure definitions
├── WM.sol                 # Allowlist management
└── Refinery.sol           # Operations utilities

test/                       # Comprehensive test suites
├── reactor/               # Reactor-specific tests
├── executor/              # Executor tests
├── e2e/                   # End-to-end integration tests
└── ...

script/                     # Deployment scripts
├── 00_DeployWM.s.sol      # Deploy allowlist manager
├── 01_UpdateWMWhitelist.s.sol # Update whitelist
├── 02_DeployRepermit.s.sol # Deploy permit system
├── 03_DeployReactor.s.sol  # Deploy main reactor
├── 04_DeployExecutor.s.sol # Deploy executor
└── input/                  # Configuration files
```

## Development Workflow

### Building
```bash
forge build  # Compiles 90 Solidity files with 0.8.20
```

### Testing
```bash
forge test   # Runs 108 tests across 14 test suites
forge test --gas-report  # Include gas usage analysis
```

### Formatting
```bash
forge fmt    # Auto-format all Solidity files
```

### Gas Analysis
```bash
forge snapshot --check  # Validate gas consumption changes
```

## Multi-Chain Deployment

The protocol is designed for deployment across multiple EVM chains with deterministic addresses via CREATE2. Configuration is managed through `script/input/config.json` with chain-specific parameters.

Supported chains include Ethereum mainnet, Arbitrum, Base, Polygon, and other major L1/L2 networks.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `forge test`
4. Format code: `forge fmt`
5. Submit pull request

## Support

- **Issues**: GitHub Issues for bug reports and feature requests
- **Documentation**: Comprehensive inline code documentation
- **Tests**: 108 test cases covering all functionality

## License

MIT License - see LICENSE file for details.