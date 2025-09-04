// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";

/// @notice Callback to validate an order
interface IValidationCallback {
    /// @notice Called by the reactor for custom validation of an order. Will revert if validation fails
    /// @param filler The filler of the order
    /// @param cosignedOrder The cosigned order to fill
    function validate(address filler, OrderLib.CosignedOrder calldata cosignedOrder) external view;
}
