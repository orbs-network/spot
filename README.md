# Spot — Limit, TWAP, Stop-Loss DeFi Protocol

**A Solidity protocol for noncustodial advanced order types on EVM.**

## Who It's For

- 🧭 **Product**: Ship price-target, time-sliced, and protective orders with professional-grade execution
- 🤝 **Business Development**: Onboard MMs/venues with transparent rev-share and attribution mechanisms
- 🧩 **Integrators**: Drop-in EIP-712 orders, cosigned prices, and modular executor architecture
- 🔧 **Developers**: Clean, well-tested Solidity codebase with comprehensive tooling

## What It Does

- 🎯 **Limit Orders**: Execute at or above a target output amount with slippage protection
- ⏱️ **TWAP Orders**: Slice total size into fixed "chunks" per configurable epoch intervals
- 🛡️ **Stop-Loss/Take-Profit**: Block execution when cosigned price breaches trigger boundaries
- 🔄 **Composable Execution**: Mix and match order types with custom exchange adapters

## Why It Wins

- ✅ **Non-custodial**: Per-order allowances via RePermit with witness-bound spending authorization
- 🔒 **Battle-tested Security**: Cosigned prices, slippage caps (max 50%), deadlines, and epoch gating
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

## Execution Flow

1. **Order Creation**: User signs EIP-712 order with chunk size, total amount, limits, epochs, and execution parameters
2. **Price Attestation**: Cosigner provides fresh price signatures with input/output token rates and timestamps
3. **Allowance Binding**: RePermit creates witness-bound spending allowance tied to exact order hash (not just cosignature)
4. **Execution**: Whitelisted executor calls reactor with order and execution parameters
5. **Validation**: Reactor validates order fields, epoch timing, cosignature freshness, and slippage bounds
6. **Settlement**: Executor runs exchange adapter via delegatecall, then reactor settles with minimum output checks
7. **Distribution**: Surplus automatically distributed between swapper and referrer according to configured shares

## Order Structure

### Core Fields

```solidity
struct Order {
    address reactor;        // OrderReactor contract address
    address executor;       // Authorized executor (enforced by reactor)
    Exchange exchange;      // Adapter, referrer, and share configuration
    address swapper;        // Order originator and token source
    uint256 nonce;          // Unique identifier per swapper
    uint256 deadline;       // Expiration timestamp
    uint32 exclusivity;     // Time-bounded exclusive execution period
    uint32 epoch;           // Seconds between fills (0 = single-use)
    uint32 slippage;        // Basis points applied to cosigned price
    uint32 freshness;       // Required cosignature age (must be > 0)
    Input input;            // Source token and amounts
    Output output;          // Destination token, limits, and recipient
}
```

### Amount Configuration

- **`input.amount`**: Per-fill "chunk" size for TWAP orders
- **`input.maxAmount`**: Total order size limit across all fills
- **`output.amount`**: Minimum acceptable output (limit price floor)
- **`output.maxAmount`**: Stop-loss trigger (reverts if cosigned price exceeds this)

### Exchange Configuration

```solidity
struct Exchange {
    address adapter;    // IExchangeAdapter implementation for swap logic
    address ref;        // Referrer address for surplus sharing
    uint32 share;       // Referrer share in basis points (0-10000)
    bytes data;         // Adapter-specific execution parameters
}
```

## Supported Order Types

### Single Limit Order
```solidity
Order memory limitOrder = Order({
    epoch: 0,                           // Single execution
    input: Input({
        amount: totalAmount,            // Full size
        maxAmount: totalAmount
    }),
    output: Output({
        amount: minOutput,              // Limit price
        maxAmount: type(uint256).max    // No stop-loss
    }),
    slippage: 50,                       // 0.5% slippage tolerance
    // ... other fields
});
```

### TWAP Order
```solidity
Order memory twapOrder = Order({
    epoch: 3600,                        // 1 hour intervals
    input: Input({
        amount: chunkSize,              // Size per execution
        maxAmount: totalSize            // Total order size
    }),
    output: Output({
        amount: minOutputPerChunk,      // Minimum per chunk
        maxAmount: type(uint256).max    // No stop-loss
    }),
    // ... other fields
});
```

### Stop-Loss Order
```solidity
Order memory stopOrder = Order({
    epoch: 0,                           // Single execution
    input: Input({
        amount: totalAmount,
        maxAmount: totalAmount
    }),
    output: Output({
        amount: 0,                      // Market order (no limit)
        maxAmount: stopTrigger          // Reverts if price exceeds
    }),
    // ... other fields
});
```

## Integration Guide

### Prerequisites

1. **Deploy Contracts**: Use provided deployment scripts with proper configuration
2. **Cosigner Service**: Implement price attestation service with EIP-712 signatures
3. **Exchange Adapter**: Create `IExchangeAdapter` implementation for your venue
4. **Executor Registration**: Get executor address whitelisted in WM contract

### Implementation Steps

#### 1. Order Definition

```solidity
import {Order, Input, Output, Exchange} from "src/Structs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

// Create order struct matching your requirements
Order memory order = Order({
    reactor: REACTOR_ADDRESS,
    executor: AUTHORIZED_EXECUTOR,
    exchange: Exchange({
        adapter: YOUR_ADAPTER,
        ref: REFERRER_ADDRESS,
        share: 250, // 2.5% referrer share
        data: abi.encode(swapParams)
    }),
    swapper: msg.sender,
    nonce: userNonce++,
    deadline: block.timestamp + 1 days,
    exclusivity: 60, // 60 seconds exclusive
    epoch: 3600,     // 1 hour TWAP
    slippage: 100,   // 1% slippage
    freshness: 300,  // 5 minute max cosig age
    input: Input({
        token: USDC,
        amount: 1000e6,     // 1000 USDC chunks
        maxAmount: 10000e6  // 10000 USDC total
    }),
    output: Output({
        token: WETH,
        amount: 0.5e18,          // Min 0.5 ETH per chunk
        maxAmount: type(uint256).max,
        recipient: msg.sender
    })
});
```

#### 2. Cosigner Implementation

```solidity
import {Cosignature, CosignedValue} from "src/Structs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

function createCosignature(
    address inputToken,
    address outputToken,
    uint256 inputValue,
    uint256 outputValue
) external view returns (Cosignature memory, bytes memory signature) {
    Cosignature memory cosig = Cosignature({
        timestamp: block.timestamp,
        reactor: REACTOR_ADDRESS,
        input: CosignedValue({
            token: inputToken,
            value: inputValue,
            decimals: IERC20Metadata(inputToken).decimals()
        }),
        output: CosignedValue({
            token: outputToken,
            value: outputValue,
            decimals: IERC20Metadata(outputToken).decimals()
        })
    });
    
    bytes32 hash = OrderLib.hash(cosig);
    bytes32 digest = IEIP712(COSIGNER).hashTypedData(hash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, digest);
    signature = abi.encodePacked(r, s, v);
    
    return (cosig, signature);
}
```

#### 3. Exchange Adapter

```solidity
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder} from "src/Structs.sol";

contract YourAdapter is IExchangeAdapter {
    function swap(
        bytes32 orderHash,
        uint256 resolvedAmountOut,
        CosignedOrder memory order,
        bytes calldata data
    ) external override {
        // Decode adapter-specific parameters
        (address router, bytes memory swapData) = abi.decode(data, (address, bytes));
        
        // Execute swap through your venue
        (bool success,) = router.call(swapData);
        require(success, "Swap failed");
        
        // Adapter must ensure minimum output is available
        uint256 outputBalance = IERC20(order.order.output.token).balanceOf(address(this));
        require(outputBalance >= resolvedAmountOut, "Insufficient output");
    }
}
```

#### 4. Executor Integration

```solidity
import {Executor} from "src/executor/Executor.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

// Deploy executor with reactor and WM addresses
Executor executor = new Executor(REACTOR_ADDRESS, WM_ADDRESS);

// Execute order (caller must be whitelisted in WM)
function fillOrder(
    CosignedOrder calldata co,
    uint256 minAmountOut
) external {
    SettlementLib.Execution memory execution = SettlementLib.Execution({
        minAmountOut: minAmountOut,
        data: abi.encode(routerAddress, swapCalldata)
    });
    
    executor.execute(co, execution);
}
```

### Security Considerations

- **Freshness Validation**: Cosignatures must be recent (within `order.freshness` seconds)
- **Epoch Enforcement**: TWAP orders cannot execute more than once per epoch window
- **Slippage Protection**: Maximum 50% slippage (4,999 BPS) enforced by constants
- **Allowlist Controls**: Only WM-approved executors can call reactor functions
- **Witness Binding**: RePermit signatures are bound to exact order hashes, preventing reuse
- **Reentrancy Guards**: All external calls protected by OpenZeppelin ReentrancyGuard
- **Safe Transfers**: All token operations use SafeERC20 with USDT compatibility

## Development Setup

### Prerequisites

- **Foundry**: Latest version with forge, cast, anvil, and chisel
- **Git**: For submodule management
- **Node.js**: Optional, for additional tooling

### Installation

```bash
# Clone repository
git clone https://github.com/orbs-network/spot.git
cd spot

# Initialize dependencies (NEVER CANCEL - takes 6-7 seconds)
git submodule update --init --recursive

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# Build project (takes ~10 seconds with 1M optimization runs)
forge build

# Run test suite (100 tests across 13 suites)
forge test

# Format code
forge fmt
```

### Build Configuration

```toml
# foundry.toml
[profile.default]
solc = "0.8.20"              # EXACT version required
optimizer_runs = 1_000_000   # Maximum gas efficiency
src = "src"
out = "out"
libs = ["lib"]
verbosity = 3
```

### Project Structure

```
├── src/
│   ├── reactor/             # Order validation and settlement
│   │   ├── OrderReactor.sol # Main reactor contract
│   │   ├── Constants.sol    # Protocol constants (BPS, MAX_SLIPPAGE)
│   │   └── lib/            # Core libraries
│   ├── repermit/           # EIP-712 permit system
│   │   ├── RePermit.sol    # Main permit contract
│   │   └── RePermitLib.sol # Permit utilities
│   ├── executor/           # Swap execution and callbacks
│   │   ├── Executor.sol    # Main executor contract
│   │   └── lib/           # Execution libraries
│   ├── adapter/            # Exchange adapters
│   │   └── DefaultDexAdapter.sol
│   ├── interface/          # Contract interfaces
│   ├── WM.sol             # Allowlist management
│   ├── Refinery.sol       # Operations utilities
│   └── Structs.sol        # Shared data structures
├── test/                   # Comprehensive test suites
│   ├── base/              # Common test utilities
│   ├── reactor/           # Reactor component tests
│   ├── executor/          # Executor component tests
│   └── *.t.sol           # Individual test files
├── script/                 # Deployment scripts
│   ├── input/config.json  # Multi-chain configuration
│   └── *.s.sol           # Deployment scripts
├── lib/                   # Git submodule dependencies
├── foundry.toml           # Build configuration
├── remappings.txt         # Import path mappings
└── .gas-snapshot         # Gas consumption baselines
```

### Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract OrderReactorTest

# Run with gas reporting
forge test --gas-report

# Run fuzz tests with custom runs
forge test --fuzz-runs 1000

# Generate gas snapshots
forge snapshot

# Check gas snapshot changes
forge snapshot --check
```

### Development Workflow

1. **Make Changes**: Edit source files in `src/`
2. **Format**: `forge fmt` (always run before commits)
3. **Build**: `forge build` (check for compilation errors)
4. **Test**: `forge test` (ensure all tests pass)
5. **Gas Check**: `forge snapshot --check` (verify no major regressions)
6. **Commit**: Git commit with descriptive message

## Deployment

### Deployment Sequence

1. **WM (Allowlist)**: `script/00_DeployWM.s.sol`
2. **Whitelist Updates**: `script/01_UpdateWMWhitelist.s.sol`
3. **RePermit**: `script/02_DeployRepermit.s.sol`
4. **OrderReactor**: `script/03_DeployReactor.s.sol`
5. **Executor**: `script/04_DeployExecutor.s.sol`

### Environment Variables

```bash
# Required for all deployments
export OWNER=0x...           # Contract owner address
export COSIGNER=0x...        # Price cosigner address
export REPERMIT=0x...        # RePermit contract address
export REACTOR=0x...         # OrderReactor contract address
export WM=0x...              # WM contract address

# Optional
export SALT=0x...            # CREATE2 salt for deterministic addresses
export RPC_URL=https://...   # Network RPC endpoint
export PRIVATE_KEY=0x...     # Deployer private key
```

### Multi-Chain Configuration

The protocol supports deployment across 16+ chains with deterministic addresses via CREATE2:

```json
{
  "chains": [
    "eth", "arb", "bnb", "matic", "ftm", "op", "linea", 
    "blast", "base", "zkevm", "manta", "sei", "sonic", 
    "zircuit", "scroll", "flare"
  ]
}
```

Each chain maintains consistent contract bytecode with chain-specific admin addresses configured in `script/input/config.json`.

### Gas Optimization

- **Optimizer Runs**: 1,000,000 for maximum runtime efficiency
- **Library Usage**: Minimal external calls through optimized libraries
- **Batch Operations**: Refinery contract for gas-efficient multi-operations
- **Exact Allowances**: Prevents unnecessary approval transactions

## Security Model

### Access Controls

- **Two-Step Ownership**: WM contract uses OpenZeppelin Ownable2Step for admin transfers
- **Executor Allowlist**: Only WM-approved addresses can execute orders
- **Sender Validation**: Orders can only be executed by their designated executor
- **Signature Verification**: EIP-712 signatures validated for both orders and cosignatures

### Validation Layers

1. **Order Validation**: Input/output amounts, token addresses, slippage bounds
2. **Epoch Enforcement**: Time-bucket controls prevent duplicate fills within windows
3. **Freshness Checks**: Cosignatures must be within configured age limits
4. **Slippage Caps**: Hard-coded maximum of 50% (4,999 BPS) slippage
5. **Price Boundaries**: Stop-loss orders revert if cosigned price exceeds triggers

### Economic Security

- **Exact Allowances**: RePermit sets precise token allowances to prevent over-spending
- **Witness Binding**: Spending authorization tied to exact order hash, not reusable
- **Surplus Distribution**: Automatic fair distribution prevents MEV extraction
- **Reentrancy Protection**: All external calls protected by OpenZeppelin guards

### Operational Security

- **Deterministic Deployments**: CREATE2 ensures consistent addresses across chains
- **Immutable References**: Core contract addresses locked at deployment
- **Event Emission**: Comprehensive logging for monitoring and compliance
- **Graceful Degradation**: Failed operations revert cleanly without state corruption

## Gas Costs

Typical gas consumption (optimized with 1M runs):

- **Order Creation**: ~50k gas (EIP-712 signature + RePermit setup)
- **Single Fill**: ~150k gas (validation + settlement + surplus distribution)
- **TWAP Fill**: ~120k gas (reduced validation for subsequent epochs)
- **Batch Operations**: ~80k base + 40k per additional operation

## Limits & Constants

```solidity
// From src/reactor/Constants.sol
uint256 public constant BPS = 10_000;           // Basis points denominator
uint256 public constant MAX_SLIPPAGE = 4_999;   // 49.99% maximum slippage

// Order constraints
uint256 public constant MIN_FRESHNESS = 1;      // Minimum cosignature age
uint256 public constant MAX_EPOCH = 2**32 - 1;  // Maximum epoch duration
```

### Validation Rules

- Slippage must be strictly less than 50% (0–4,999 BPS)
- Cosignature freshness must be > 0 and < epoch (when epoch != 0)
- Input amount must be > 0 and ≤ maxAmount
- Output amount must be ≤ maxAmount
- Input token cannot be zero address
- Output recipient cannot be zero address
- Epoch = 0 enables single execution only

## Troubleshooting

### Common Build Issues

```bash
# Submodule initialization failed
git submodule update --init --recursive --force

# Compilation errors
forge clean && forge build

# Test failures
forge test -vvv  # Verbose output for debugging
```

### Runtime Issues

- **"InvalidSignature"**: Check EIP-712 domain separator and signature format
- **"Expired"**: Verify order deadline and cosignature freshness
- **"InvalidSender"**: Ensure executor is whitelisted in WM contract
- **"InsufficientAllowance"**: Check RePermit allowance and spending tracking
- **"CosignedMaxAmount"**: Cosigned price exceeds stop-loss trigger

### Integration Issues

- **Adapter Failures**: Verify delegatecall context and return values
- **Gas Estimation**: Account for variable adapter gas costs
- **Token Compatibility**: Test with fee-on-transfer and rebasing tokens
- **Slippage Calculation**: Ensure proper basis point arithmetic

## Contributing

1. **Fork Repository**: Create personal fork for development
2. **Create Branch**: Use descriptive branch names (`feature/xyz`, `fix/abc`)
3. **Write Tests**: Add comprehensive test coverage for new features
4. **Format Code**: Run `forge fmt` before committing
5. **Test Thoroughly**: Ensure `forge test` passes completely
6. **Submit PR**: Include detailed description and test results

### Code Standards

- **Solidity 0.8.20**: Exact version required for consistency
- **NatSpec Comments**: Document all public functions and complex logic
- **Gas Optimization**: Consider 1M optimizer runs in design decisions
- **Security First**: Favor safety over gas savings in critical paths
- **Comprehensive Testing**: Unit, integration, and fuzz test coverage

## License

MIT License - see LICENSE file for details.

---

**Production Deployments**: See `script/input/config.json` for deployed contract addresses across supported networks.

**Security Audits**: Contact team for latest audit reports and security documentation.

**Support**: Open GitHub issues for bugs, feature requests, or integration questions.