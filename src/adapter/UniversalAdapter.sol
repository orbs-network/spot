// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/// @title UniversalAdapter
/// @notice Executes swap logic by temporarily approving and externally calling an arbitrary target.
contract UniversalAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

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

        IERC20(co.order.input.token).forceApprove(x.target, co.order.input.amount);
        Address.functionCall(x.target, x.data);
        IERC20(co.order.input.token).forceApprove(x.target, 0);
    }
}
