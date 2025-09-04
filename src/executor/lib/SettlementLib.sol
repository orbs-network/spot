// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ResolvedOrder, OutputToken} from "src/interface/CallbackStructs.sol";
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
        OutputToken fee;
        uint256 minAmountOut;
        bytes data;
    }

    function settle(ResolvedOrder memory order, Execution memory execution, address reactor, address exchange)
        internal
    {
        if (order.outputs.length != 1) revert InvalidOrder();

        address outToken = address(order.outputs[0].token);
        uint256 outAmount = order.outputs[0].amount;
        address recipient = order.outputs[0].recipient;

        TokenLib.prepareFor(outToken, reactor, outAmount);
        if (execution.minAmountOut > outAmount) {
            TokenLib.transfer(outToken, recipient, execution.minAmountOut - outAmount);
        }

        // Send gas fee to specified recipient if amount > 0
        if (execution.fee.amount > 0) {
            TokenLib.transfer(execution.fee.token, execution.fee.recipient, execution.fee.amount);
        }

        emit Settled(
            order.hash,
            order.info.swapper,
            exchange,
            address(order.input.token),
            outToken,
            order.input.amount,
            outAmount
        );
    }
}
