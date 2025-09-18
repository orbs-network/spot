// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {OrderLib} from "src/libs/OrderLib.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

    function delegateSwap(bytes32, /*hash*/ uint256, /*resolvedAmountOut*/ CosignedOrder memory co, Execution memory x)
        external
        override
    {
        SafeERC20.forceApprove(IERC20(co.order.input.token), router, co.order.input.amount);
        Address.functionCall(router, x.data);
    }
}
