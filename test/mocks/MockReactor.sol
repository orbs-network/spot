// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

contract MockReactor is IReactor {
    // Tracking fields used by unit tests
    CosignedOrder public lastOrder;
    address public lastExchange;
    SettlementLib.Execution public lastExecution;
    address public lastSender;

    function executeWithCallback(CosignedOrder calldata cosignedOrder, SettlementLib.Execution calldata execution)
        external
        payable
    {
        // record for tests
        lastSender = msg.sender;
        lastOrder = cosignedOrder;
        lastExchange = cosignedOrder.order.exchange.adapter;
        lastExecution = execution;

        bytes32 orderHash = OrderLib.hash(cosignedOrder.order);
        // For mock purposes, we'll use a dummy resolvedAmountOut = co.order.output.amount
        uint256 resolvedAmountOut = cosignedOrder.order.output.amount;
        IReactorCallback(msg.sender).reactorCallback(orderHash, resolvedAmountOut, cosignedOrder, execution);
    }

    receive() external payable {}
}
