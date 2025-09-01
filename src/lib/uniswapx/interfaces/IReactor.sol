// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "../base/ReactorStructs.sol";

/// @notice Interface for order execution reactors
interface IReactor {
    /// @notice Execute a single order using the given callback data
    /// @param order The order definition and valid signature to execute
    /// @param callbackData The callbackData to pass to the callback
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData) external payable;
}
