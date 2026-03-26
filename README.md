# Spot — Limit, TWAP, Stop-Loss, Take-Profit Non-Custodial Decentralized DeFi Protocol

**Agent-ready decentralized DeFi protocol for non-custodial advanced order types on EVM chains.**

**🔒 [Security Audit Report](./Audit-AstraSec.pdf)** - Smart contracts professionally audited by AstraSec

## Agent Entry

Start with these files:

1. [`SKILL.md`](./SKILL.md) for the execution workflow
2. [`manifest.json`](./manifest.json) for machine-readable discovery
3. [`skill/scripts/order.js`](./skill/scripts/order.js) for prepare, submit, and query operations

The skill bundle is available through these surfaces:

1. Repo-local root `SKILL.md`, `manifest.json`, and the `skill/` support directory
2. Hosted raw files from [`https://orbs-network.github.io/spot/`](https://orbs-network.github.io/spot/), with root entrypoints plus `skill/` support paths
3. The npm package `@orbs-network/spot`
4. MCP clients through the package bin `spot-mcp`, published in `server.json` as `io.github.orbs-network/spot`

## Agent Capabilities

- 🎯 **Intent Mapping**: Translate user intent into market, limit, TWAP, stop-loss, take-profit, and delayed-start orders
- ✍️ **Signing Prep**: Produce approval calldata, EIP-712 typed data, and relay-ready payloads
- 🔎 **Machine Discovery**: Read supported chains, runtime addresses, references, and assets from `manifest.json`
- 🧰 **Direct Execution Tooling**: Use `skill/scripts/order.js` for prepare, submit, and query flows

## Protocol Guarantees

- ✅ **Non-custodial**: Per-order allowances via RePermit with witness-bound spending authorization
- 🔒 **Oracle-Protected**: Trigger checks, slippage caps, freshness windows, and deadline enforcement
- 🛡️ **Battle-Tested**: Audited contracts, verified runtime components, and comprehensive test coverage
- 🏗️ **Production Ready**: Multi-chain deployments plus repo-shipped skill files, helper scripts, config, and ABIs

## Architecture

### Core Components

- 🧠 **OrderReactor** (`src/OrderReactor.sol`): Validates orders, checks epoch constraints, computes minimum output from cosigned prices, and settles via inlined implementation with reentrancy protection. Includes emergency pause functionality controlled by WM allowlist.
- ✍️ **RePermit** (`src/RePermit.sol`): Permit2-style EIP-712 signatures with witness data that binds spending allowances to exact order hashes, preventing signature reuse
- 🧾 **Cosigner** (`src/ops/Cosigner.sol`): Attests to trigger-time and current market prices (input/output ratios) with proper token validation
- 🛠️ **Executor** (`src/Executor.sol`): Whitelisted fillers that run venue logic via delegatecall to adapters, ensure minimum output requirements, and distribute surplus
- 🔐 **WM** (`src/ops/WM.sol`): Two-step ownership allowlist manager for executors and admin functions with event emission
- 🏭 **Refinery** (`src/ops/Refinery.sol`): Operations utility for batching multicalls and sweeping token balances by basis points

### Key Libraries

- **OrderLib** (`src/lib/OrderLib.sol`): EIP-712 structured data hashing for orders and cosignatures
- **OrderValidationLib** (`src/lib/OrderValidationLib.sol`): Order field validation (amounts, tokens, slippage caps)
- **ResolutionLib** (`src/lib/ResolutionLib.sol`): Price resolution logic using cosigned rates with slippage protection
- **EpochLib** (`src/lib/EpochLib.sol`): Time-bucket management for TWAP order execution intervals
- **CosignatureLib** (`src/lib/CosignatureLib.sol`): Cosigner validation and freshness checking
- **ExclusivityOverrideLib** (`src/lib/ExclusivityOverrideLib.sol`): Time-bounded exclusivity with override mechanics
- **SurplusLib** (`src/lib/SurplusLib.sol`): Automatic surplus distribution between swappers and referrers
- **SettlementLib** (`src/lib/SettlementLib.sol`): Token transfer coordination with gas fee handling
- **TokenLib** (`src/lib/TokenLib.sol`): Safe token operations with ETH/ERC20 abstraction

## Order Structure

Based on `src/Structs.sol`, each order contains:

```solidity
struct Order {
    address reactor;           // OrderReactor contract address
    address executor;          // Authorized executor for this order
    Exchange exchange;         // Adapter, referrer, and data
    address swapper;           // Order creator/signer
    uint256 nonce;            // Unique identifier
    uint256 start;        // Earliest execution timestamp
    uint256 deadline;         // Expiration timestamp
    uint256 chainid;          // Chain ID for cross-chain validation
    uint32 exclusivity;       // BPS-bounded exclusive execution
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
    uint256 limit;            // Minimum acceptable output (limit)
    uint256 triggerLower;     // Lower trigger boundary (stop-loss style)
    uint256 triggerUpper;     // Upper trigger boundary (take-profit style)
    address recipient;        // Where to send output tokens
}

```

## Flow (Plain English)

1. **Order Creation**: User signs one EIP-712 order with chunk size, total amount, limits, slippage tolerance, epoch interval, and deadline
2. **Price Attestation**: Cosigner signs both trigger and current market price data (input/output token ratios)
3. **Execution**: Whitelisted executor calls `Executor.execute()` with order and execution parameters
4. **Validation**: OrderReactor validates signatures, checks epoch windows, enforces `start`, checks trigger/current timestamp ordering, and applies slippage protection
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
        limit: 950 ether,       // Minimum acceptable output
        triggerLower: 0,         // No lower trigger gate
        triggerUpper: 0          // No upper trigger gate
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
        limit: 95 ether,        // Minimum per chunk
        triggerLower: 0,
        triggerUpper: 0
    })
});
```

### Stop-Loss / Take-Profit Order
```solidity
Order memory order = Order({
    // ... standard fields
    epoch: 0,                    // Single execution
    start: block.timestamp,  // Order becomes active immediately
    output: Output({
        limit: 900 ether,        // Minimum per chunk output when executing
        triggerLower: 950 ether, // Stop-loss boundary per chunk
        triggerUpper: 1200 ether // Take-profit boundary per chunk
    })
});
```



## Security Model

### Access Controls
- **WM Allowlist**: WM-gated entrypoints restrict privileged admin operations; order execution honors exclusivity rules (setting `exclusivity > 0` allows any filler who satisfies the higher min-output requirement)
- **Two-Step Ownership**: `WM` uses OpenZeppelin's `Ownable2Step` for secure ownership transfers
- **Executor Binding**: Orders specify authorized executor; only that executor can fill the order
- **Non-Exclusive Fillers**: `exclusivity = 0` locks fills to the designated executor; setting it above zero invites third-party fillers who must meet a higher minimum output (scaled by the BPS override). Choose a non-zero value only when you intentionally want open competition on callbacks.

### Validation Layers
- **Order Validation**: `OrderValidationLib.validate()` checks all order fields for validity
- **Signature Verification**: RePermit validates EIP-712 signatures and witness data binding
- **Epoch Enforcement**: `EpochLib.update()` prevents early/duplicate fills within time windows
- **Slippage Protection**: Maximum 50% slippage cap enforced in `Constants.MAX_SLIPPAGE`
- **Freshness Windows**: Current cosignatures expire after configurable time periods
- **Trigger Timestamp Rules**: Trigger timestamp must be after `start` and not later than the current timestamp

### Economic Security
- **Witness-Bound Spending**: RePermit ties allowances to exact order hashes, preventing signature reuse
- **Surplus Distribution**: Automatic fair distribution of any excess tokens between swapper and referrer
- **Exact Allowances**: `SafeERC20.forceApprove()` prevents allowance accumulation attacks

### Operational Security
- **Reentrancy Protection**: `OrderReactor` is protected with `ReentrancyGuard`; `Executor` and `Refinery` rely on WM gating and internal invariants instead
- **Safe Token Handling**: Comprehensive support for USDT-like tokens and ETH
- **Delegatecall Isolation**: Adapters run in controlled executor context with proper validation
- **Emergency Pause**: OrderReactor can be paused by WM-allowed addresses to halt order execution during emergencies

## Limits & Constants

- **Maximum Slippage**: up to 5,000 BPS (50%) inclusive - defined in `src/Constants.sol`
- **Basis Points**: 10,000 BPS = 100% - standard denomination for all percentage calculations
- **Freshness Requirements**: Must be > 0 seconds; must be < epoch duration when epoch != 0
- **Epoch Behavior**: 0 = single execution, >0 = recurring with specified interval
- **Gas Optimization**: 1,000,000 optimizer runs for maximum efficiency



## Development Workflow

### Building
```bash
forge build  # Compiles 90 Solidity files with 0.8.27
```

### Testing
```bash
forge test   # Runs the full Foundry suite
forge test --gas-report  # Include gas usage analysis
```

### Formatting
```bash
forge fmt    # Auto-format all Solidity files
```

## Multi-Chain Deployment

The protocol is designed for deployment across EVM-compatible chains with deterministic addresses via CREATE2. Configuration is managed through `config.json`; populate this file with the parameters required for the target network.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `forge test`
4. Format code: `forge fmt`
5. Submit pull request

## Operational Notes

- **Executor ETH Refunds**: Order execution returns the reactor's ETH balance to the filler. Keep executors funded and treat unexpected reactor ETH as recoverable by any WM-allowed address.
- **Input Tokens**: Orders must spend ERC-20 tokens; wrap native ETH before creating orders.

## Support

- **Issues**: GitHub Issues for bug reports and feature requests
- **Documentation**: Comprehensive inline code documentation

## License

MIT License - see LICENSE file for details.
