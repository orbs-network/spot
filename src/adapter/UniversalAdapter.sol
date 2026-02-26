// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/// @title UniversalAdapter
/// @notice Calls any target using fill-time target and calldata.
contract UniversalAdapter is IExchangeAdapter {
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
        if (x.target == address(0)) revert InvalidTarget();

        SafeERC20.forceApprove(IERC20(co.order.input.token), x.target, co.order.input.amount);
        Address.functionCall(x.target, x.data);
        SafeERC20.forceApprove(IERC20(co.order.input.token), x.target, 0);
    }
}
