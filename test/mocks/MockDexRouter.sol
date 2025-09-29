// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * @title MockDexRouter
 * @notice Simplified mock router for testing
 */
contract MockDexRouter {
    bool public shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function doSwap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address to) external {
        if (shouldFail) revert("Mock swap failed");

        // Transfer input tokens from caller
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Mint output tokens to recipient
        ERC20Mock(tokenOut).mint(to, amountOut);
    }
}
