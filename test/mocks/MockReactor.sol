// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

contract MockReactor is IReactor {
    // Tracking fields used by unit tests
    OrderLib.CosignedOrder public lastOrder;
    address public lastExchange;
    SettlementLib.Execution public lastExecution;
    address public lastSender;

    function executeWithCallback(
        OrderLib.CosignedOrder calldata cosignedOrder,
        address exchange,
        SettlementLib.Execution calldata execution
    ) external payable {
        // record for tests
        lastSender = msg.sender;
        lastOrder = cosignedOrder;
        lastExchange = exchange;
        lastExecution = execution;

        bytes32 orderHash = OrderLib.hash(cosignedOrder.order);
        IReactorCallback(msg.sender).reactorCallback(cosignedOrder, orderHash, exchange, execution);
    }

    receive() external payable {}
}
