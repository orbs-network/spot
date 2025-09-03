# DefaultDexAdapter

The `DefaultDexAdapter` is a generic exchange adapter that implements the standard DEX router pattern of approve + swap. It is designed to work with any DEX router that follows the common pattern used by Uniswap V2/V3, SushiSwap, and similar protocols.

## Features

- **Generic Router Support**: Works with any router that accepts pre-approved tokens and encoded function calls
- **ETH Support**: Handles both ERC20 and ETH input tokens
- **USDT-Safe**: Uses `forceApprove` to handle tokens with non-standard approval behavior
- **Security-First**: Resets approvals to 0 after swaps to minimize attack surface
- **Delegate Call Safe**: Designed to work within the Executor's delegatecall context

## Usage

### Data Format

The adapter expects the router address and call data encoded directly as the `data` parameter:

```solidity
bytes memory data = abi.encode(router, callData);
```

Where:
- `router` is the address of the DEX router contract
- `callData` is the encoded swap function call

### Example Usage

```solidity
// For ERC20 -> ERC20 swap via Uniswap V2
address[] memory path = [tokenA, tokenB];
bytes memory swapCall = abi.encodeWithSelector(
    IUniswapV2Router.swapExactTokensForTokens.selector,
    amountIn,
    amountOutMin,
    path,
    recipient,
    deadline
);

bytes memory data = abi.encode(uniswapV2Router, swapCall);
```

### Supported Patterns

The adapter supports these common DEX router patterns:

1. **ERC20 to ERC20**: `swapExactTokensForTokens`
2. **ETH to ERC20**: `swapExactETHForTokens`
3. **ERC20 to ETH**: `swapExactTokensForETH`
4. **Multi-hop swaps**: Any router function that accepts path arrays
5. **Custom router functions**: Any function that expects pre-approved tokens

## Security Considerations

### Approval Management
- Sets exact approval amount before swap
- Resets approval to 0 after swap for security
- Uses `forceApprove` for USDT-like token compatibility

### Router Validation
- Validates router address is not zero
- Reverts on failed router calls
- Does not whitelist specific routers (left to order validation)

### Execution Context
- Runs in delegatecall context within Executor
- Assumes Executor has sufficient input token balance
- Does not directly handle output tokens (Executor handles settlement)

## Integration Checklist

When integrating with the DefaultDexAdapter:

1. **Router Compatibility**: Ensure your DEX router follows the approve + swap pattern
2. **Function Encoding**: Properly encode the router function call with correct parameters  
3. **Path Configuration**: Set up correct token paths for multi-hop swaps
4. **Slippage Protection**: Include appropriate `amountOutMin` values
5. **Gas Limits**: Account for approval + swap gas costs
6. **Error Handling**: Handle `InvalidRouter` and `SwapFailed` errors appropriately

## Supported DEX Protocols

The adapter is compatible with any router implementing these patterns:

- ✅ Uniswap V2 / Sushiswap style routers
- ✅ Uniswap V3 router (with appropriate encoding)  
- ✅ Balancer V2 router
- ✅ 1inch router
- ✅ Custom DEX routers following approve + swap pattern
- ❌ DEX protocols requiring special permit/signature schemes
- ❌ Protocols requiring multiple transaction flows

## Testing

The adapter includes comprehensive tests covering:

- ERC20 to ERC20 swaps
- ETH to ERC20 swaps
- USDT-like token handling
- Error conditions
- Integration with Executor
- Approval reset behavior

Run tests with:
```bash
forge test --match-contract DefaultDexAdapter
```