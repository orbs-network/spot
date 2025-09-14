// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Constants} from "src/reactor/Constants.sol";

library ResolutionLib {
    using Math for uint256;

    error CosignedMaxAmount();

    function resolve(OrderLib.CosignedOrder memory cosigned) internal pure returns (uint256) {
        uint256 cosignedOutput = cosigned.order.input.amount.mulDiv(
            cosigned.cosignatureData.output.value, cosigned.cosignatureData.input.value
        );

        if (cosignedOutput > cosigned.order.output.maxAmount) revert CosignedMaxAmount();

        uint256 minOut = cosignedOutput.mulDiv(Constants.BPS - cosigned.order.slippage, Constants.BPS);
        return minOut.max(cosigned.order.output.amount);
    }
}
