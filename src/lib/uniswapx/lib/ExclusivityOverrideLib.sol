// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "src/reactor/Constants.sol";

library ExclusivityOverrideLib {
    using Math for uint256;

    error InvalidSender();
    function applyOverride(
        uint256 minOut,
        address exclusiveExecutor,
        uint32 exclusivityBps
    ) internal view returns (uint256) {
        if (msg.sender != exclusiveExecutor && exclusivityBps == 0) revert InvalidSender();
        if (msg.sender == exclusiveExecutor) return minOut;
        uint256 bps = Constants.BPS + uint256(exclusivityBps);
        return Math.mulDiv(minOut, bps, Constants.BPS, Math.Rounding.Up);
    }
}
