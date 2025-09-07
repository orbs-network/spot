// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(
        OrderLib.CosignedOrder calldata cosignedOrder,
        SettlementLib.Execution calldata execution
    ) external payable;
}
