// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CosignedOrder} from "src/reactor/lib/OrderStructs.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(CosignedOrder calldata co, SettlementLib.Execution calldata x) external payable;
}
