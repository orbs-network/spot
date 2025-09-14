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
        uint256 minAmountOut;
        OrderLib.Output fee;
        bytes data;
    }

    function settle(bytes32 hash, OrderLib.CosignedOrder memory co, Execution memory x) internal {
        TokenLib.prepareFor(co.order.output.token, msg.sender, co.order.output.amount);
        if (x.minAmountOut > co.order.output.amount) {
            TokenLib.transfer(co.order.output.token, co.order.output.recipient, x.minAmountOut - co.order.output.amount);
        }

        // Send gas fee to specified recipient if amount > 0
        if (x.fee.amount > 0) {
            TokenLib.transfer(x.fee.token, x.fee.recipient, x.fee.amount);
        }

        emit Settled(
            hash,
            co.order.info.swapper,
            co.order.exchange.adapter,
            co.order.input.token,
            co.order.output.token,
            co.order.input.amount,
            co.order.output.amount
        );
    }
}
