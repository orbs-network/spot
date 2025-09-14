// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {CosignedOrder} from "src/Structs.sol";

interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(CosignedOrder calldata co, SettlementLib.Execution calldata x) external payable;
}
