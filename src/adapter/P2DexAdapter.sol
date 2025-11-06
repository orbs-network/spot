// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPermit2} from "src/interface/IPermit2.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/**
 * @title P2DexAdapter
 * @notice Exchange adapter for routers that require both router and Permit2 allowances
 */
contract P2DexAdapter is IExchangeAdapter {
    address public immutable router;
    address public immutable permit2;

    /// @param _router DEX router that executes swaps.
    /// @param _permit2 Permit2 contract authorising router allowances.
    constructor(address _router, address _permit2) {
        router = _router;
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
        IPermit2(permit2).approve(co.order.input.token, router, type(uint160).max, type(uint48).max);
        SafeERC20.forceApprove(IERC20(co.order.input.token), permit2, co.order.input.amount);
        SafeERC20.forceApprove(IERC20(co.order.input.token), router, co.order.input.amount);

        Address.functionCall(router, x.data);

        SafeERC20.forceApprove(IERC20(co.order.input.token), router, 0);
        SafeERC20.forceApprove(IERC20(co.order.input.token), permit2, 0);
    }
}
