// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CosignedOrder} from "src/Structs.sol";
import {Constants} from "src/reactor/Constants.sol";

/// @title Order resolution library
/// @notice Computes minimum output amounts from cosigned prices with slippage protection
library ResolutionLib {
    using Math for uint256;

    error CosignedExceedsStop();

    /// @dev Computes the minimum output amount for an order based on cosigned price data
    /// 1. Calculate expected output from cosigned input/output price ratio, normalizing for differing token decimals
    /// 2. Check if market price has hit stop-loss trigger or reverts with CosignedExceedsStop
    /// 3. Apply slippage protection to reduce expected output by slippage BPS
    /// 4. Return the maximum of slippage-adjusted amount and user's limit price (limit)
    function resolve(CosignedOrder memory cosigned) internal pure returns (uint256) {
        uint256 numerator = cosigned.order.input.amount;
        uint256 denominator = cosigned.cosignatureData.output.value;

        uint8 inputDecimals = cosigned.cosignatureData.input.decimals;
        uint8 outputDecimals = cosigned.cosignatureData.output.decimals;

        if (outputDecimals >= inputDecimals) {
            numerator *= 10 ** uint256(outputDecimals - inputDecimals);
        } else {
            denominator *= 10 ** uint256(inputDecimals - outputDecimals);
        }

        uint256 cosignedOutput = Math.mulDiv(numerator, cosigned.cosignatureData.input.value, denominator);

        // Treat stop=0 as type(uint256).max (no trigger)
        uint256 effectiveStop = cosigned.order.output.stop == 0 ? type(uint256).max : cosigned.order.output.stop;
        if (cosignedOutput > effectiveStop) revert CosignedExceedsStop();

        uint256 minOut = cosignedOutput.mulDiv(Constants.BPS - cosigned.order.slippage, Constants.BPS);
        return minOut.max(cosigned.order.output.limit);
    }
}
