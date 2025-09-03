// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {ResolvedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title DefaultDexAdapter
 * @notice A generic exchange adapter for standard DEX routers using approve + swap pattern
 * @dev This adapter works with any DEX router that follows the standard pattern of:
 *      1. Approve router to spend input tokens
 *      2. Call router's swap function with provided call data
 */
contract DefaultDexAdapter is IExchangeAdapter {
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    /**
     * @notice Executes a token swap through a DEX router
     * @param order The resolved order containing input/output token information
     * @param data Call data to pass directly to the router
     */
    function swap(ResolvedOrder memory order, bytes calldata data) external override {
        _forceApprove(IERC20(address(order.input.token)), router, order.input.amount);
        Address.functionCall(router, data);
    }

    /**
     * @dev Force approve that works with non-standard tokens like USDT
     * @param token Token to approve
     * @param spender Address to approve
     * @param value Amount to approve
     */
    function _forceApprove(IERC20 token, address spender, uint256 value) private {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);

        (bool success, bytes memory returndata) = address(token).call(approvalCall);

        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            // If approve failed, try to reset allowance first
            bytes memory resetCall = abi.encodeWithSelector(token.approve.selector, spender, 0);
            Address.functionCall(address(token), resetCall);
            Address.functionCall(address(token), approvalCall);
        }
    }
}
