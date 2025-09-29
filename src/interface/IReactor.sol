// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {Execution} from "src/Structs.sol";

/// @title Order reactor interface
/// @notice Interface for order validation, settlement, and executor callback execution
interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(CosignedOrder calldata co, Execution calldata x) external payable;
}
