// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IWM} from "src/interface/IWM.sol";

/// @title WM allowlist base contract
/// @notice Provides standardized onlyAllowed modifier for contracts using WM allowlist
abstract contract WMAllowed {
    /// @dev Thrown when caller is not allowed by WM.
    error NotAllowed();

    /// @dev The WM contract address used for allowlist checking
    address public immutable wm;

    constructor(address _wm) {
        wm = _wm;
    }

    /// @dev Modifier to restrict access to addresses allowed by WM
    modifier onlyAllowed() {
        if (!IWM(wm).allowed(msg.sender)) revert NotAllowed();
        _;
    }

    /// @dev Reverts if the caller is not allowed by the WM contract
    /// @param _wm The WM contract address to check against
    function _requireAllowed(address _wm) internal view {
        if (!IWM(_wm).allowed(msg.sender)) revert NotAllowed();
    }

    /// @dev Reverts if the specified address is not allowed by the WM contract
    /// @param _wm The WM contract address to check against
    /// @param caller The address to check (allows checking addresses other than msg.sender)
    function _requireAllowed(address _wm, address caller) internal view {
        if (!IWM(_wm).allowed(caller)) revert NotAllowed();
    }

    /// @dev Returns true if the caller is allowed by the WM contract
    /// @param _wm The WM contract address to check against
    function _isAllowed(address _wm) internal view returns (bool) {
        return IWM(_wm).allowed(msg.sender);
    }

    /// @dev Returns true if the specified address is allowed by the WM contract
    /// @param _wm The WM contract address to check against
    /// @param caller The address to check
    function _isAllowed(address _wm, address caller) internal view returns (bool) {
        return IWM(_wm).allowed(caller);
    }
}
