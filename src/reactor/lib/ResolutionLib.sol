// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Constants} from "src/reactor/Constants.sol";

library ResolutionLib {
    using Math for uint256;

    error CosignedMaxAmount();
    error InvalidSender();

    function resolve(OrderLib.CosignedOrder memory cosigned) internal view returns (uint256) {
        uint256 outAmount = resolveOutAmount(cosigned);
        return applyExclusivityOverride(outAmount, cosigned.order.executor, cosigned.order.exclusivity);
    }

    function resolveOutAmount(OrderLib.CosignedOrder memory cosigned) private pure returns (uint256 outAmount) {
        uint256 cosignedOutput = cosigned.order.input.amount.mulDiv(
            cosigned.cosignatureData.output.value, cosigned.cosignatureData.input.value
        );

        if (cosignedOutput > cosigned.order.output.maxAmount) revert CosignedMaxAmount();

        uint256 minOut = cosignedOutput.mulDiv(Constants.BPS - cosigned.order.slippage, Constants.BPS);
        outAmount = minOut.max(cosigned.order.output.amount);
    }

    function applyExclusivityOverride(uint256 minOut, address exclusiveExecutor, uint32 exclusivityBps)
        private
        view
        returns (uint256)
    {
        if (msg.sender != exclusiveExecutor && exclusivityBps == 0) revert InvalidSender();
        if (msg.sender == exclusiveExecutor) return minOut;
        uint256 bps = Constants.BPS + uint256(exclusivityBps);
        return Math.mulDiv(minOut, bps, Constants.BPS, Math.Rounding.Up);
    }
}
