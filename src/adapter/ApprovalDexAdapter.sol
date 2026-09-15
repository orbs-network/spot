// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/// @notice Adapter for routers whose token approval target is a separate contract.
contract ApprovalDexAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable spender;

    constructor(address _router, address _spender) {
        router = _router;
        spender = _spender;
    }

    /// @inheritdoc IExchangeAdapter
    function delegateSwap(bytes32, uint256, CosignedOrder memory co, Execution memory x) external override {
        if (x.target != router) revert InvalidTarget();
        IERC20 inputToken = IERC20(co.order.input.token);
        inputToken.forceApprove(spender, co.order.input.amount);
        Address.functionCall(router, x.data);
        inputToken.forceApprove(spender, 0);
    }
}
