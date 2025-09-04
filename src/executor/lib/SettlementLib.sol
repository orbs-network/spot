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

    function settle(
        OrderLib.CosignedOrder memory cosignedOrder,
        Execution memory execution,
        address reactor,
        address exchange,
        bytes32 orderHash
    ) internal {
        TokenLib.prepareFor(cosignedOrder.order.output.token, reactor, cosignedOrder.order.output.amount);
        if (execution.minAmountOut > cosignedOrder.order.output.amount) {
            TokenLib.transfer(
                cosignedOrder.order.output.token,
                cosignedOrder.order.output.recipient,
                execution.minAmountOut - cosignedOrder.order.output.amount
            );
        }

        // Send gas fee to specified recipient if amount > 0
        if (execution.fee.amount > 0) {
            TokenLib.transfer(execution.fee.token, execution.fee.recipient, execution.fee.amount);
        }

        emit Settled(
            orderHash,
            cosignedOrder.order.info.swapper,
            exchange,
            cosignedOrder.order.input.token,
            cosignedOrder.order.output.token,
            cosignedOrder.order.input.amount,
            cosignedOrder.order.output.amount
        );
    }
}
