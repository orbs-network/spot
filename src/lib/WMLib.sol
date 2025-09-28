// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IWM} from "src/interface/IWM.sol";

/// @title WM allowlist library
/// @notice Provides standardized WM allowlist checking functionality
library WMLib {
    error NotAllowed();

    /// @dev Reverts if the caller is not allowed by the WM contract
    /// @param wm The WM contract address to check against
    function requireAllowed(address wm) internal view {
        if (!IWM(wm).allowed(msg.sender)) revert NotAllowed();
    }

    /// @dev Reverts if the specified address is not allowed by the WM contract
    /// @param wm The WM contract address to check against
    /// @param caller The address to check (allows checking addresses other than msg.sender)
    function requireAllowed(address wm, address caller) internal view {
        if (!IWM(wm).allowed(caller)) revert NotAllowed();
    }

    /// @dev Returns true if the caller is allowed by the WM contract
    /// @param wm The WM contract address to check against
    function isAllowed(address wm) internal view returns (bool) {
        return IWM(wm).allowed(msg.sender);
    }

    /// @dev Returns true if the specified address is allowed by the WM contract
    /// @param wm The WM contract address to check against
    /// @param caller The address to check
    function isAllowed(address wm, address caller) internal view returns (bool) {
        return IWM(wm).allowed(caller);
    }
}
