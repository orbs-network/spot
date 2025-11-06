// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {TokenLib} from "src/lib/TokenLib.sol";
import {Output, CosignedOrder, Execution} from "src/Structs.sol";

/// @title Settlement library
/// @notice Handles token transfers and fee distribution for order execution
library SettlementLib {
    using Math for uint256;

    error InvalidOrder();
    error InsufficientPostSwapBalance(uint256 balance, uint256 resolved, uint256 fees, uint256 required);

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

    /// @dev Minimal balance guard for the primary output token; BI-focused sanity check.
    function guard(uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x) internal view {
        address outToken = co.order.output.token;
        uint256 fees;
        for (uint256 i; i < x.fees.length; i++) {
            if (x.fees[i].token == outToken) {
                fees += x.fees[i].limit;
            }
        }
        uint256 required = resolvedAmountOut.max(x.minAmountOut) + fees;
        uint256 balance = TokenLib.balanceOf(outToken);
        if (balance < required) revert InsufficientPostSwapBalance(balance, resolvedAmountOut, fees, required);
    }

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

        for (uint256 i; i < x.fees.length; i++) {
            Output memory fee = x.fees[i];
            TokenLib.transfer(fee.token, fee.recipient, fee.limit);
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
