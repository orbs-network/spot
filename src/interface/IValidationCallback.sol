// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CosignedOrder} from "src/reactor/lib/OrderStructs.sol";

/// @notice Callback to validate an order
interface IValidationCallback {
    /// @notice Called by the reactor for custom validation of an order. Will revert if validation fails
    /// @param filler The filler of the order
    /// @param co The cosigned order to fill
    function validate(address filler, CosignedOrder calldata co) external view;
}
