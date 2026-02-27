// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Order} from "src/Structs.sol";
import {Constants} from "src/Constants.sol";

/// @title Order validation library
/// @notice Validates order structure and enforces business logic constraints including chain ID verification
library OrderValidationLib {
    // Address validation errors
    error InvalidOrderReactorZero();
    error InvalidOrderExecutorZero();
    error InvalidOrderAdapterZero();
    error InvalidOrderSwapperZero();

    error InvalidOrderInputAmountZero();
    error InvalidOrderInputAmountGtMax();
    error InvalidOrderStartZero();
    error InvalidOrderStartInFuture();
    error InvalidOrderTriggerRange();
    error InvalidOrderSlippageTooHigh();
    error InvalidOrderInputTokenZero();
    error InvalidOrderOutputRecipientZero();
    error InvalidOrderReactorMismatch();
    error InvalidOrderDeadlineExpired();
    error InvalidOrderChainid();
    error InvalidOrderExchangeShareBps();
    error InvalidOrderSameToken();

    /// @dev Validates order structure and business logic constraints for security
    /// 1. Ensures critical addresses are non-zero (reactor, executor, adapter, swapper)
    /// 2. Validates timing constraints (deadline not expired, correct chain ID)
    /// 3. Ensures reactor address matches the calling contract (prevents cross-reactor attacks)
    /// 4. Validates token amounts and limits (non-zero input, amounts within max limits)
    /// 5. Enforces protocol limits (slippage caps, referrer share limits)
    function validate(Order memory order) internal view {
        // Validate non-zero critical addresses
        if (order.reactor == address(0)) revert InvalidOrderReactorZero();
        if (order.reactor != address(this)) revert InvalidOrderReactorMismatch();
        if (order.executor == address(0)) revert InvalidOrderExecutorZero();
        if (order.exchange.adapter == address(0)) revert InvalidOrderAdapterZero();
        if (order.swapper == address(0)) revert InvalidOrderSwapperZero();
        if (order.chainid != block.chainid) revert InvalidOrderChainid();

        if (order.start == 0) revert InvalidOrderStartZero();
        if (order.start > block.timestamp) revert InvalidOrderStartInFuture();
        if (order.deadline <= block.timestamp) revert InvalidOrderDeadlineExpired();

        if (order.input.amount == 0) revert InvalidOrderInputAmountZero();
        if (order.input.amount > order.input.maxAmount) revert InvalidOrderInputAmountGtMax();
        if (order.output.triggerUpper != 0 && order.output.triggerLower > order.output.triggerUpper) {
            revert InvalidOrderTriggerRange();
        }
        if (order.slippage > Constants.MAX_SLIPPAGE) revert InvalidOrderSlippageTooHigh();
        if (order.input.token == address(0)) revert InvalidOrderInputTokenZero();
        if (order.output.recipient == address(0)) revert InvalidOrderOutputRecipientZero();
        if (order.input.token == order.output.token) revert InvalidOrderSameToken();
        if (order.exchange.share > Constants.BPS) revert InvalidOrderExchangeShareBps();
    }
}
