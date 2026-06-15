// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPermit2} from "src/interface/IPermit2.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/**
 * @title DynamicP2DexAdapter
 * @notice Exchange adapter for Permit2 routers selected at fill time.
 */
contract DynamicP2DexAdapter is IExchangeAdapter {
    address public immutable permit2;

    /// @param _permit2 Permit2 contract authorising fill-time target allowances.
    constructor(address _permit2) {
        permit2 = _permit2;
    }

    /// @inheritdoc IExchangeAdapter
    function delegateSwap(
        bytes32,
        /*hash*/
        uint256,
        /*resolvedAmountOut*/
        CosignedOrder memory co,
        Execution memory x
    )
        external
        override
    {
        address target = x.target;
        if (target == address(0)) revert InvalidTarget();

        IPermit2(permit2).approve(co.order.input.token, target, type(uint160).max, type(uint48).max);
        SafeERC20.forceApprove(IERC20(co.order.input.token), permit2, co.order.input.amount);
        SafeERC20.forceApprove(IERC20(co.order.input.token), target, co.order.input.amount);

        Address.functionCall(target, x.data);

        SafeERC20.forceApprove(IERC20(co.order.input.token), target, 0);
        SafeERC20.forceApprove(IERC20(co.order.input.token), permit2, 0);
    }
}
