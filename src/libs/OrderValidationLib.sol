// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/libs/OrderLib.sol";
import {Order} from "src/Structs.sol";
import {Constants} from "src/reactor/Constants.sol";

library OrderValidationLib {
    // Address validation errors
    error InvalidOrderReactorZero();
    error InvalidOrderExecutorZero();
    error InvalidOrderAdapterZero();
    error InvalidOrderSwapperZero();

    error InvalidOrderInputAmountZero();
    error InvalidOrderInputAmountGtMax();
    error InvalidOrderOutputAmountGtMax();
    error InvalidOrderSlippageTooHigh();
    error InvalidOrderInputTokenZero();
    error InvalidOrderOutputRecipientZero();
    error InvalidOrderReactorMismatch();
    error InvalidOrderDeadlineExpired();
    error InvalidOrderChainid();
    error InvalidOrderExchangeShareBps();

    function validate(Order memory order) internal view {
        // Validate non-zero critical addresses
        if (order.reactor == address(0)) revert InvalidOrderReactorZero();
        if (order.executor == address(0)) revert InvalidOrderExecutorZero();
        if (order.exchange.adapter == address(0)) revert InvalidOrderAdapterZero();
        if (order.swapper == address(0)) revert InvalidOrderSwapperZero();

        if (order.deadline <= block.timestamp) revert InvalidOrderDeadlineExpired();
        if (order.chainid != block.chainid) revert InvalidOrderChainid();

        if (order.reactor != address(this)) revert InvalidOrderReactorMismatch();
        if (order.input.amount == 0) revert InvalidOrderInputAmountZero();
        if (order.input.amount > order.input.maxAmount) revert InvalidOrderInputAmountGtMax();
        if (order.output.amount > order.output.maxAmount) revert InvalidOrderOutputAmountGtMax();
        if (order.slippage >= Constants.MAX_SLIPPAGE) revert InvalidOrderSlippageTooHigh();
        if (order.input.token == address(0)) revert InvalidOrderInputTokenZero();
        if (order.output.recipient == address(0)) revert InvalidOrderOutputRecipientZero();
        if (order.exchange.share > Constants.BPS) revert InvalidOrderExchangeShareBps();
    }
}
