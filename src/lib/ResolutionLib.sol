// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {Constants} from "src/reactor/Constants.sol";

/// @title Order resolution library
/// @notice Computes minimum output amounts from cosigned prices with slippage protection
library ResolutionLib {
    using Math for uint256;

    error CosignedExceedsStop();

    /// @dev Computes the minimum output amount for an order based on cosigned price data
    /// 1. Calculate expected output from cosigned input/output price ratio
    /// 2. Check if market price has hit stop-loss trigger or reverts with CosignedExceedsStop
    /// 3. Apply slippage protection to reduce expected output by slippage BPS
    /// 4. Return the maximum of slippage-adjusted amount and user's limit price (limit)
    function resolve(CosignedOrder memory cosigned) internal pure returns (uint256) {
        uint256 cosignedOutput = cosigned.order.input.amount.mulDiv(
            cosigned.cosignatureData.output.value, cosigned.cosignatureData.input.value
        );

        if (cosignedOutput > cosigned.order.output.stop) revert CosignedExceedsStop();

        uint256 minOut = cosignedOutput.mulDiv(Constants.BPS - cosigned.order.slippage, Constants.BPS);
        return minOut.max(cosigned.order.output.limit);
    }
}
