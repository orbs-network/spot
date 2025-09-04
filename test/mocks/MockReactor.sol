// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

contract MockReactor is IReactor {
    // Tracking fields used by unit tests
    OrderLib.CosignedOrder internal _lastOrder;
    bytes public lastCallbackData;
    address public lastSender;

    function executeWithCallback(OrderLib.CosignedOrder calldata cosignedOrder, bytes calldata callbackData) external payable {
        // record for tests
        lastSender = msg.sender;
        _lastOrder = cosignedOrder;
        lastCallbackData = callbackData;

        OrderLib.ResolvedOrder[] memory ros = new OrderLib.ResolvedOrder[](1);

        OrderLib.OutputToken[] memory outs = new OrderLib.OutputToken[](1);
        outs[0] = OrderLib.OutputToken({token: address(cosignedOrder.order.output.token), amount: 500, recipient: cosignedOrder.order.info.swapper});

        address adapter = cosignedOrder.order.exchange.adapter;

        ros[0] = OrderLib.ResolvedOrder({
            info: OrderLib.OrderInfo({
                reactor: address(this),
                swapper: cosignedOrder.order.info.swapper,
                nonce: 1,
                deadline: 1_086_400,
                additionalValidationContract: address(0),
                additionalValidationData: abi.encode(adapter)
            }),
            input: OrderLib.InputToken({token: address(cosignedOrder.order.input.token), amount: 100, maxAmount: 100}),
            outputs: outs,
            sig: cosignedOrder.signature,
            hash: bytes32(uint256(123))
        });

        IReactorCallback(msg.sender).reactorCallback(ros, callbackData);
    }

    receive() external payable {}
}
