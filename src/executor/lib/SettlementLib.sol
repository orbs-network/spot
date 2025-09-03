// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ResolvedOrder, OutputToken} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

library SettlementLib {
    error InvalidOrder();

    struct Execution {
        OutputToken fee;
        uint256 minAmountOut;
        bytes data;
    }

    struct SettlementResult {
        bytes32 orderHash;
        address swapper;
        address inToken;
        address outToken;
        uint256 inAmount;
        uint256 outAmount;
    }

    function settle(ResolvedOrder memory order, Execution memory execution, address reactor)
        internal
        returns (SettlementResult memory result)
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

        result = SettlementResult({
            orderHash: order.hash,
            swapper: order.info.swapper,
            inToken: address(order.input.token),
            outToken: outToken,
            inAmount: order.input.amount,
            outAmount: outAmount
        });
    }
}