// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OrderLib} from "src/lib/OrderLib.sol";
import {TokenLib} from "src/lib/TokenLib.sol";
import {Output, CosignedOrder, Execution} from "src/Structs.sol";

/// @title Settlement library
/// @notice Handles token transfers and fee distribution for order execution
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

    /// @dev Handles final settlement of an executed order
    /// 1. Prepares output tokens for transfer by setting approval to the reactor
    /// 2. If minimum output exceeds resolved amount, transfers the difference to recipient
    /// 3. Transfers any execution fees to the designated fee recipient
    /// 4. Emits settlement event with execution details
    function settle(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x) internal {
        TokenLib.prepareFor(co.order.output.token, msg.sender, resolvedAmountOut);
        if (x.minAmountOut > resolvedAmountOut) {
            TokenLib.transfer(co.order.output.token, co.order.output.recipient, x.minAmountOut - resolvedAmountOut);
        }

        TokenLib.transfer(x.fee.token, x.fee.recipient, x.fee.limit);

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
