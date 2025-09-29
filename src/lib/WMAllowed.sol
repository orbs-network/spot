// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

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
}
