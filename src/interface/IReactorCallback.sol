// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

/// @notice Callback for executing orders through a reactor.
interface IReactorCallback {
    /// @notice Called by the reactor during the execution of an order
    /// @param cosignedOrder The cosigned order being executed
    /// @param orderHash The hash of the order
    /// @param exchange The exchange adapter address
    /// @param execution The execution parameters
    /// @dev Must have approved each token and amount in outputs to the msg.sender
    function reactorCallback(
        OrderLib.CosignedOrder memory cosignedOrder,
        bytes32 orderHash,
        address exchange,
        SettlementLib.Execution memory execution
    ) external;
}
