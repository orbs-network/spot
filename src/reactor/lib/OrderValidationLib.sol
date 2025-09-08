// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Constants} from "src/reactor/Constants.sol";
import {IValidationCallback} from "src/interface/IValidationCallback.sol";

library OrderValidationLib {
    error InvalidOrderInputAmountZero();
    error InvalidOrderInputAmountGtMax();
    error InvalidOrderOutputAmountGtMax();
    error InvalidOrderSlippageTooHigh();
    error InvalidOrderInputTokenZero();
    error InvalidOrderOutputRecipientZero();

    function validate(OrderLib.Order memory order) internal pure {
        if (order.input.amount == 0) revert InvalidOrderInputAmountZero();
        if (order.input.amount > order.input.maxAmount) revert InvalidOrderInputAmountGtMax();
        if (order.output.amount > order.output.maxAmount) revert InvalidOrderOutputAmountGtMax();
        if (order.slippage >= Constants.MAX_SLIPPAGE) revert InvalidOrderSlippageTooHigh();
        if (order.input.token == address(0)) revert InvalidOrderInputTokenZero();
        if (order.output.recipient == address(0)) revert InvalidOrderOutputRecipientZero();
    }

    /// @notice Call additional validation callback if specified
    /// @param executor The executor calling the validation
    /// @param co The cosigned order to validate
    function validateAdditional(address executor, OrderLib.CosignedOrder memory co) internal view {
        if (co.order.info.additionalValidationContract != address(0)) {
            IValidationCallback(co.order.info.additionalValidationContract).validate(executor, co);
        }
    }
}
