# Liquidity Hub to Spot Migration Guide

## Overview

This guide provides step-by-step instructions for migrating from Liquidity Hub to Spot, including which features to implement and how to map existing functionality.

## Feature Mapping Table

| Liquidity Hub Feature | Spot Equivalent | Status | Notes |
|----------------------|-----------------|--------|-------|
| Single Orders | Limit Orders (epoch=0) | ✅ Exists | Direct mapping |
| Partial Orders | TWAP Orders (epoch>0) | ⚠️ Similar | Different mechanics |
| Executor with Multicall | Executor + Adapters | ✅ Exists | More modular in Spot |
| Surplus Distribution | SurplusLib | ✅ Exists | More sophisticated in Spot |
| WETH Unwrapping (DeltaExecutor) | N/A | ❌ Missing | **Needs implementation** |
| Admin Contract | WM | ⚠️ Partial | **Needs enhancement** |
| RePermit | RePermit | ✅ Exists | Similar implementation |
| Refinery | Refinery | ✅ Exists | Similar implementation |

## Recommended Implementation: Hybrid Approach

### Phase 1: Add High-Value Missing Features

#### 1.1 DeltaExecutor Implementation

**Purpose**: Enable seamless WETH → ETH unwrapping during order execution

**Files to Create:**
- `src/executor/DeltaExecutor.sol`
- `test/DeltaExecutor.t.sol`
- `script/05_DeployDeltaExecutor.s.sol`

**Implementation Steps:**

```solidity
// src/executor/DeltaExecutor.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IReactor} from "../interface/IReactor.sol";
import {IReactorCallback} from "../interface/IReactorCallback.sol";
import {Order, CosignedOrder, Execution} from "../Structs.sol";
import {TokenLib} from "../lib/TokenLib.sol";
import {WMAllowed} from "../lib/WMAllowed.sol";
import {IWETH} from "../interface/IWETH.sol";

/// @title DeltaExecutor
/// @notice Specialized executor for WETH unwrapping scenarios
/// @dev Handles input tokens with optional WETH → ETH conversion
contract DeltaExecutor is IReactorCallback, WMAllowed {
    using TokenLib for address;

    error InvalidSender(address sender);
    error InvalidOrder();

    IReactor public immutable reactor;
    IWETH public immutable weth;

    event WETHUnwrapped(address indexed recipient, uint256 amount);

    constructor(address _reactor, address _weth, address _wm) WMAllowed(_wm) {
        reactor = IReactor(_reactor);
        weth = IWETH(_weth);
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) revert InvalidSender(msg.sender);
        _;
    }

    /// @notice Execute order with callback
    /// @param order The cosigned order to execute
    /// @param execution Execution parameters including unwrap flag in data
    function execute(CosignedOrder calldata order, Execution calldata execution) 
        external 
        onlyAllowed 
    {
        reactor.execute(order, execution, abi.encode(msg.sender));
    }

    /// @notice Reactor callback to handle WETH unwrapping
    /// @param order The resolved order
    /// @param data Encoded recipient address
    function reactorCallback(Order memory order, bytes memory data) 
        external 
        override 
        onlyReactor 
    {
        address recipient = abi.decode(data, (address));
        
        // Check if unwrapping is requested via exchange.data
        bool shouldUnwrap = _shouldUnwrap(order.exchange.data);
        
        // Handle input token (WETH)
        uint256 balance = order.input.token.balanceOf(address(this));
        if (balance > 0) {
            if (shouldUnwrap && address(order.input.token) == address(weth)) {
                weth.withdraw(balance);
                payable(recipient).transfer(balance);
                emit WETHUnwrapped(recipient, balance);
            } else {
                order.input.token.transfer(recipient, balance);
            }
        }
        
        // Approve output tokens back to reactor
        uint256 outputBalance = order.output.token.balanceOf(address(this));
        if (outputBalance > 0) {
            order.output.token.approve(address(reactor), outputBalance);
        }
    }

    function _shouldUnwrap(bytes memory data) private pure returns (bool) {
        if (data.length == 0) return false;
        return abi.decode(data, (bool));
    }

    receive() external payable {
        // Accept ETH from WETH.withdraw()
    }
}
```

**Test File:**

```solidity
// test/DeltaExecutor.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import {DeltaExecutor} from "../src/executor/DeltaExecutor.sol";
import {BaseTest} from "./base/BaseTest.sol";

contract DeltaExecutorTest is BaseTest {
    DeltaExecutor public deltaExecutor;
    
    function setUp() public override {
        super.setUp();
        // Deploy DeltaExecutor with WETH address
        deltaExecutor = new DeltaExecutor(
            address(reactor),
            address(weth),
            address(wm)
        );
        
        // Add to allowlist
        vm.prank(owner);
        wm.allow(address(deltaExecutor), true);
    }
    
    function test_unwrapWETH() public {
        // Test WETH unwrapping scenario
        // Implementation based on Spot's test patterns
    }
    
    function test_normalExecution() public {
        // Test normal execution without unwrapping
    }
}
```

#### 1.2 WM Enhancement for Fund Recovery

**Purpose**: Add admin withdrawal and recovery functions to WM

**Files to Modify:**
- `src/ops/WM.sol`

**Changes:**

```solidity
// Add to WM.sol

/// @notice Withdraw tokens from contract (emergency recovery)
/// @param tokens Array of token addresses to withdraw (address(0) for ETH)
function withdraw(address[] calldata tokens) external onlyOwner {
    for (uint256 i = 0; i < tokens.length; i++) {
        if (tokens[i] == address(0)) {
            // Withdraw ETH
            uint256 balance = address(this).balance;
            if (balance > 0) {
                payable(owner()).transfer(balance);
            }
        } else {
            // Withdraw ERC20
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(owner(), balance);
            }
        }
    }
}

/// @notice Execute arbitrary multicall (emergency operations)
/// @param calls Array of calls to execute
function emergencyMulticall(IMulticall3.Call[] calldata calls) 
    external 
    onlyOwner 
{
    // Execute using Multicall3Lib
    Multicall3Lib.aggregate(calls);
}

receive() external payable {
    // Accept ETH for recovery scenarios
}
```

**Test Updates:**

```solidity
// Add to test/WM.t.sol

function test_withdraw_ETH() public {
    // Send ETH to WM
    vm.deal(address(wm), 1 ether);
    
    uint256 balanceBefore = owner.balance;
    
    // Withdraw
    vm.prank(owner);
    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    wm.withdraw(tokens);
    
    assertEq(owner.balance, balanceBefore + 1 ether);
    assertEq(address(wm).balance, 0);
}

function test_withdraw_ERC20() public {
    // Test ERC20 withdrawal
}

function test_emergencyMulticall() public {
    // Test emergency multicall execution
}
```

### Phase 2: Documentation and Mapping

#### 2.1 Order Type Mapping

Create helper documentation showing how to create Spot orders that replicate LH behavior:

**LH Single Order → Spot Limit Order:**

```javascript
// Liquidity Hub
const lhOrder = {
  info: { ... },
  exclusiveFiller: executor,
  exclusivityOverrideBps: 0,
  input: { token: WETH, amount: 1000000 },
  outputs: [{ token: USDC, amount: 2500000, recipient: swapper }]
}

// Spot Equivalent
const spotOrder = {
  reactor: orderReactor,
  executor: executor,
  exchange: { adapter, ref, share, data },
  swapper: swapper,
  nonce: nonce,
  deadline: deadline,
  chainid: 1,
  exclusivity: 0, // or non-zero for open competition
  epoch: 0, // SINGLE USE - key difference
  slippage: 500, // 5% in bps
  freshness: 60, // 60 seconds
  input: { 
    token: WETH, 
    amount: 1000000, // chunk size
    maxAmount: 1000000 // same as amount for single order
  },
  output: { 
    token: USDC, 
    limit: 2500000, // minimum acceptable
    stop: type(uint256).max, // no stop trigger
    recipient: swapper 
  }
}
```

**LH Partial Order → Spot TWAP Order:**

```javascript
// Liquidity Hub - Partial fill of 10 ETH order
const lhPartialOrder = {
  info: { ... },
  exclusiveFiller: executor,
  exclusivityOverrideBps: 0,
  input: { token: WETH, amount: 10000000 }, // 10 WETH total
  outputs: [{ token: USDC, amount: 25000000, recipient: swapper }]
}
// Fill with outAmount = 2500000 (1 WETH worth)
// Input calculated as: (10000000 * 2500000) / 25000000 = 1000000

// Spot TWAP Equivalent
const spotTwapOrder = {
  reactor: orderReactor,
  executor: executor,
  exchange: { adapter, ref, share, data },
  swapper: swapper,
  nonce: nonce,
  deadline: deadline,
  chainid: 1,
  exclusivity: 0,
  epoch: 3600, // 1 hour intervals - KEY FOR PARTIAL BEHAVIOR
  slippage: 500,
  freshness: 60,
  input: { 
    token: WETH, 
    amount: 1000000, // 1 WETH per chunk
    maxAmount: 10000000 // 10 WETH total
  },
  output: { 
    token: USDC, 
    limit: 2500000, // per chunk minimum
    stop: type(uint256).max,
    recipient: swapper 
  }
}
// Executes up to 10 times (10 WETH / 1 WETH chunks)
// Each execution must wait 3600 seconds (epoch interval)
```

**Key Differences:**
- LH partial fills can happen anytime in any amount
- Spot TWAP fills happen at fixed intervals with fixed chunk sizes
- Spot provides better protection against manipulation via epochs
- Spot adds cosigned price validation for safety

#### 2.2 SDK/Frontend Migration

**LH SDK Pattern:**
```typescript
// Liquidity Hub
const order = await liquidityHub.createPartialOrder({
  input: { token: WETH, amount: totalAmount },
  outputs: [{ token: USDC, amount: totalOutput, recipient }]
});

// Execute partial fill
await liquidityHub.execute(order, partialOutAmount);
```

**Spot SDK Pattern:**
```typescript
// Spot - TWAP for similar behavior
const order = await spot.createOrder({
  input: { 
    token: WETH, 
    amount: chunkSize,
    maxAmount: totalAmount 
  },
  output: { 
    token: USDC, 
    limit: minOutputPerChunk,
    stop: type(uint256).max,
    recipient 
  },
  epoch: intervalSeconds, // Key parameter
  // ... other params
});

// Execute (can be called multiple times respecting epoch)
await spot.execute(cosignedOrder, execution);
```

### Phase 3: Testing and Validation

#### 3.1 Migration Test Suite

Create comprehensive tests validating LH → Spot migration:

```solidity
// test/migration/LHToSpotMigration.t.sol
pragma solidity 0.8.27;

import {BaseTest} from "../base/BaseTest.sol";

contract LHToSpotMigrationTest is BaseTest {
    function test_LHSingleOrder_asSpotLimit() public {
        // Create Spot limit order (epoch=0)
        // Validate same behavior as LH single order
    }
    
    function test_LHPartialOrder_asSpotTWAP() public {
        // Create Spot TWAP order
        // Execute multiple times
        // Validate cumulative behavior matches LH partial fills
    }
    
    function test_DeltaExecutor_WETHUnwrap() public {
        // Validate WETH unwrapping works as in LH
    }
}
```

#### 3.2 Integration Testing

```bash
# Run full test suite
forge test

# Run migration-specific tests
forge test --match-path test/migration/LHToSpotMigration.t.sol

# Gas comparison
forge snapshot --check
```

### Phase 4: Deployment

#### 4.1 Deployment Order

1. Deploy core contracts (if not already deployed):
   - WM
   - RePermit
   - OrderReactor
   - Executor

2. Deploy new contracts:
   - DeltaExecutor (if implementing WETH unwrapping)

3. Update configurations:
   - Add DeltaExecutor to WM allowlist
   - Configure adapters

4. Deploy on all target chains:
   - Use CREATE2 for deterministic addresses
   - Verify contracts

#### 4.2 Configuration Migration

```json
// script/input/config.json
{
  "chains": {
    "1": {
      "name": "Ethereum Mainnet",
      "wm": "0x...",
      "repermit": "0x...",
      "reactor": "0x...",
      "executor": "0x...",
      "deltaExecutor": "0x...", // NEW
      "adapters": {
        "paraswap": "0x...",
        "default": "0x..."
      },
      "weth": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    }
  }
}
```

### Phase 5: User Migration

#### 5.1 Communication Plan

**Migration Announcement:**
- Explain benefits of Spot over LH (cosigned prices, stop-loss, etc.)
- Provide migration timeline
- Share documentation and examples

**User Education:**
- How to create limit orders (LH single → Spot limit)
- How to create TWAP orders (LH partial → Spot TWAP)
- When to use each order type

**Support Period:**
- Run both systems in parallel for transition period
- Gradual cutover with support
- Monitor for edge cases

#### 5.2 Allowlist Migration

```typescript
// Migration Script
async function migrateAllowlist() {
  // Get LH allowlist
  const lhAllowed = await getLiquidityHubAllowlist();
  
  // Add to Spot WM
  for (const address of lhAllowed) {
    await spotWM.allow([address], true);
  }
  
  console.log(`Migrated ${lhAllowed.length} addresses`);
}
```

## Partial Order Reactor (Optional - Phase 6)

If analysis shows true partial fill semantics are required:

### Implementation Overview

```solidity
// src/reactor/PartialOrderReactor.sol
contract PartialOrderReactor is IReactor {
    // Port LH's PartialOrderReactor with Spot's security features
    // Add cosigned price validation
    // Add chain ID validation
    // Integrate with existing WM allowlist
}

// src/lib/PartialOrderLib.sol
library PartialOrderLib {
    // Port LH's partial order structures
    // Add Spot's additional validation
}
```

### When to Implement

Only implement if:
1. Analysis shows TWAP cannot satisfy critical use cases
2. Market makers require arbitrary partial fills
3. User demand justifies development effort

### Estimated Effort

- Implementation: 1-2 weeks
- Testing: 1 week
- Deployment: 1 week
- Total: 3-4 weeks

## Success Metrics

### Technical Metrics
- [ ] All Spot tests passing
- [ ] DeltaExecutor tests passing
- [ ] Gas costs comparable to LH
- [ ] Security audit passed (if new features added)

### Migration Metrics
- [ ] 100% of LH allowlist migrated
- [ ] >90% of LH order types mappable to Spot
- [ ] <10% user friction reports
- [ ] Zero security incidents

### Performance Metrics
- [ ] Order execution latency < LH baseline
- [ ] Gas costs within 5% of LH
- [ ] Surplus distribution accuracy 100%

## Rollback Plan

If migration encounters issues:

1. **Keep LH Contracts Active**: Don't deprecate until Spot proven
2. **Dual-Run Period**: Run both systems for 2-4 weeks
3. **Monitoring**: Track all metrics closely
4. **Fast Rollback**: Documented procedure to revert if needed

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1: Core Features | 1 week | DeltaExecutor, WM enhancements |
| Phase 2: Documentation | 3 days | Mapping guides, SDK examples |
| Phase 3: Testing | 1 week | Migration tests, validation |
| Phase 4: Deployment | 3 days | Multi-chain deployment |
| Phase 5: User Migration | 2-4 weeks | Allowlist migration, support |
| Phase 6: Partial Orders (Optional) | 3-4 weeks | If required |

**Total (Required)**: 5-7 weeks
**Total (With Partial Orders)**: 8-11 weeks

## Conclusion

The migration from Liquidity Hub to Spot is primarily a **feature upgrade** rather than a lateral move. Spot provides:

✅ **More Security**: Cosigned prices, slippage caps, chain ID validation
✅ **More Features**: Stop-loss, TWAP, epoch controls
✅ **Better Architecture**: Modular adapters, comprehensive libraries

The main additions needed are:
1. **DeltaExecutor**: WETH unwrapping convenience (~3 days)
2. **WM Enhancements**: Fund recovery functions (~2 days)
3. **Documentation**: Order mapping and migration guides (~2 days)

Most Liquidity Hub functionality maps cleanly to Spot's existing features, making this a high-value migration with moderate implementation effort.
