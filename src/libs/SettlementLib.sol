// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/libs/OrderLib.sol";
import {TokenLib} from "src/libs/TokenLib.sol";
import {Output, CosignedOrder, Execution} from "src/Structs.sol";

library SettlementLib {
    error InvalidOrder();

    event Settled(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed exchange,
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount,
        uint256 minOut
    );

    // Execution struct is defined in src/Structs.sol

    function settle(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x) internal {
        TokenLib.prepareFor(co.order.output.token, msg.sender, resolvedAmountOut);
        if (x.minAmountOut > resolvedAmountOut) {
            TokenLib.transfer(co.order.output.token, co.order.output.recipient, x.minAmountOut - resolvedAmountOut);
        }

        if (x.fee.amount > 0) {
            TokenLib.transfer(x.fee.token, x.fee.recipient, x.fee.amount);
        }

        emit Settled(
            hash,
            co.order.swapper,
            co.order.exchange.adapter,
            co.order.input.token,
            co.order.output.token,
            co.order.input.amount,
            resolvedAmountOut,
            x.minAmountOut
        );
    }
}
