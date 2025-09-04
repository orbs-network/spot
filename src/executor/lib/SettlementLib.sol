// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

library SettlementLib {
    error InvalidOrder();

    event Settled(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed exchange,
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount
    );

    struct Execution {
        OrderLib.Output fee;
        uint256 minAmountOut;
        bytes data;
    }

    function settle(OrderLib.CosignedOrder memory cosignedOrder, Execution memory execution, address reactor, address exchange)
        internal
    {
        address outToken = cosignedOrder.order.output.token;
        uint256 outAmount = cosignedOrder.order.output.amount;
        address recipient = cosignedOrder.order.output.recipient;

        TokenLib.prepareFor(outToken, reactor, outAmount);
        if (execution.minAmountOut > outAmount) {
            TokenLib.transfer(outToken, recipient, execution.minAmountOut - outAmount);
        }

        // Send gas fee to specified recipient if amount > 0
        if (execution.fee.amount > 0) {
            TokenLib.transfer(execution.fee.token, execution.fee.recipient, execution.fee.amount);
        }

        emit Settled(
            OrderLib.hash(cosignedOrder.order),
            cosignedOrder.order.info.swapper,
            exchange,
            cosignedOrder.order.input.token,
            outToken,
            cosignedOrder.order.input.amount,
            outAmount
        );
    }
}
