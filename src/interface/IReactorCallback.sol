// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {CosignedOrder} from "src/types/OrderTypes.sol";

/// @notice Callback for executing orders through a reactor.
interface IReactorCallback {
    /// @notice Called by the reactor during the execution of an order
    /// @param hash The hash of the order
    /// @param co The cosigned order being executed
    /// @param x The execution parameters
    /// @dev Must have approved each token and amount in outputs to the msg.sender
    function reactorCallback(bytes32 hash, CosignedOrder memory co, SettlementLib.Execution memory x) external;
}
