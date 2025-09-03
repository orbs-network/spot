// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {ResolvedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DefaultDexAdapter
 * @notice A generic exchange adapter for standard DEX routers using approve + swap pattern
 * @dev This adapter works with any DEX router that follows the standard pattern of:
 *      1. Approve router to spend input tokens
 *      2. Call router's swap function with encoded parameters
 */
contract DefaultDexAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

    error InvalidRouter();
    error SwapFailed();

    struct SwapParams {
        address router; // DEX router address
        bytes callData; // Encoded swap function call
    }

    /**
     * @notice Executes a token swap through a DEX router
     * @param order The resolved order containing input/output token information
     * @param data ABI-encoded SwapParams containing router address and call data
     */
    function swap(ResolvedOrder memory order, bytes calldata data) external override {
        SwapParams memory params = abi.decode(data, (SwapParams));

        if (params.router == address(0)) revert InvalidRouter();

        address inputToken = address(order.input.token);
        uint256 inputAmount = order.input.amount;

        // Handle ETH input - no approval needed
        if (inputToken == address(0)) {
            // For ETH swaps, call router with value
            (bool success,) = params.router.call{value: inputAmount}(params.callData);
            if (!success) revert SwapFailed();
            return;
        }

        // For ERC20 tokens, approve router then call swap
        IERC20(inputToken).forceApprove(params.router, inputAmount);

        (bool swapSuccess,) = params.router.call(params.callData);
        if (!swapSuccess) revert SwapFailed();

        // Reset approval to 0 for security (USDT-safe)
        IERC20(inputToken).forceApprove(params.router, 0);
    }
}
