// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {ResolvedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title DefaultDexAdapter
 * @notice A generic exchange adapter for standard DEX routers using approve + swap pattern
 * @dev This adapter works with any DEX router that follows the standard pattern of:
 *      1. Approve router to spend input tokens
 *      2. Call router's swap function with encoded parameters
 */
contract DefaultDexAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Executes a token swap through a DEX router
     * @param order The resolved order containing input/output token information
     * @param data ABI-encoded router address and call data: abi.encode(router, callData)
     */
    function swap(ResolvedOrder memory order, bytes calldata data) external override {
        (address router, bytes memory callData) = abi.decode(data, (address, bytes));

        address inputToken = address(order.input.token);
        uint256 inputAmount = order.input.amount;

        // Handle ETH input - no approval needed
        if (inputToken == address(0)) {
            // For ETH swaps, call router with value
            Address.functionCallWithValue(router, callData, inputAmount);
            return;
        }

        // For ERC20 tokens, approve router then call swap
        IERC20(inputToken).forceApprove(router, inputAmount);

        Address.functionCall(router, callData);

        // Reset approval to 0 for security (USDT-safe)
        IERC20(inputToken).forceApprove(router, 0);
    }
}
