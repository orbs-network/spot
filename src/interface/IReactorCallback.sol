// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {Execution} from "src/Structs.sol";

/// @title Reactor callback interface
/// @notice Callback for executing orders through a reactor
interface IReactorCallback {
    /// @notice Called by the reactor during the execution of an order
    /// @param hash The hash of the order
    /// @param resolvedAmountOut The resolved output amount
    /// @param co The cosigned order being executed
    /// @param x The execution parameters
    /// @dev Must have approved each token and amount in outputs to the msg.sender
    function reactorCallback(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x)
        external;
}
