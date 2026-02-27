// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CosignedOrder, Cosignature} from "src/Structs.sol";
import {Constants} from "src/Constants.sol";

/// @title Order resolution library
/// @notice Computes minimum output amounts from cosigned prices with slippage protection
library ResolutionLib {
    using Math for uint256;

    error NotTriggered();

    /// @dev Computes the minimum output amount for an order based on trigger/current cosigned prices
    /// 1. Trigger check uses the historical trigger cosignature against triggerLower/triggerUpper
    /// 2. Pricing/min-out calculation uses the current cosignature with slippage applied
    /// 3. Return the maximum of slippage-adjusted amount and user's limit price (limit)
    function resolve(CosignedOrder memory cosigned) internal pure returns (uint256) {
        if (!triggered(
                outputFromCosignature(cosigned.order.input.amount, cosigned.trigger),
                cosigned.order.output.triggerLower,
                cosigned.order.output.triggerUpper
            )) {
            revert NotTriggered();
        }

        uint256 minOut = outputFromCosignature(cosigned.order.input.amount, cosigned.current)
            .mulDiv(Constants.BPS - cosigned.order.slippage, Constants.BPS);
        return minOut.max(cosigned.order.output.limit);
    }

    function outputFromCosignature(uint256 inputAmount, Cosignature memory cosignature)
        private
        pure
        returns (uint256 outputAmount)
    {
        uint256 numerator = inputAmount;
        uint256 denominator = cosignature.output.value;
        if (cosignature.output.decimals >= cosignature.input.decimals) {
            numerator *= 10 ** uint256(cosignature.output.decimals - cosignature.input.decimals);
        } else {
            denominator *= 10 ** uint256(cosignature.input.decimals - cosignature.output.decimals);
        }
        outputAmount = numerator.mulDiv(cosignature.input.value, denominator);
    }

    function triggered(uint256 triggerOutput, uint256 triggerLower, uint256 triggerUpper) private pure returns (bool) {
        if (triggerLower != 0 && triggerOutput <= triggerLower) return true;
        if (triggerUpper != 0 && triggerOutput >= triggerUpper) return true;
        return triggerLower == 0 && triggerUpper == 0;
    }
}
