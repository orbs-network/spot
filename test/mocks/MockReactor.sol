// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

contract MockReactor is IReactor {
    // Tracking fields used by unit tests
    OrderLib.CosignedOrder internal lastOrder;
    bytes public lastCallbackData;
    address public lastSender;
    
    function getLastOrder() external view returns (OrderLib.CosignedOrder memory) {
        return lastOrder;
    }

    function executeWithCallback(OrderLib.CosignedOrder calldata cosignedOrder, bytes calldata callbackData) external payable {
        // record for tests
        lastSender = msg.sender;
        lastOrder = cosignedOrder;
        lastCallbackData = callbackData;

        OrderLib.CosignedOrder[] memory cosignedOrders = new OrderLib.CosignedOrder[](1);
        cosignedOrders[0] = cosignedOrder;

        IReactorCallback(msg.sender).reactorCallback(cosignedOrders, callbackData);
    }

    receive() external payable {}
}
