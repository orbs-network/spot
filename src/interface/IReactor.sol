// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/libs/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {Execution} from "src/Structs.sol";

interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(CosignedOrder calldata co, Execution calldata x) external payable;
}
