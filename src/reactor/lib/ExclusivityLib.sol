// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "src/reactor/Constants.sol";

library ExclusivityLib {
    error InvalidSender();

    /// @notice Apply exclusivity override to minimum amount out
    /// @param minOut The base minimum amount out
    /// @param exclusiveExecutor The address that has exclusive access
    /// @param exclusivityBps The exclusivity override in basis points
    /// @return The adjusted minimum amount out after applying exclusivity rules
    function applyExclusivityOverride(uint256 minOut, address exclusiveExecutor, uint32 exclusivityBps)
        internal
        view
        returns (uint256)
    {
        if (msg.sender != exclusiveExecutor && exclusivityBps == 0) revert InvalidSender();
        if (msg.sender == exclusiveExecutor) return minOut;
        uint256 bps = Constants.BPS + uint256(exclusivityBps);
        return Math.mulDiv(minOut, bps, Constants.BPS, Math.Rounding.Up);
    }
}
