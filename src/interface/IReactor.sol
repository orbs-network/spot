// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";

interface IReactor {
    /// @notice Execute a CosignedOrder with callback
    function executeWithCallback(OrderLib.CosignedOrder calldata cosignedOrder, bytes calldata callbackData)
        external
        payable;
}