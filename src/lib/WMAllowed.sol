// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {WMLib} from "src/lib/WMLib.sol";

/// @title WM allowlist base contract
/// @notice Provides standardized onlyAllowed modifier for contracts using WM allowlist
abstract contract WMAllowed {
    /// @dev The WM contract address used for allowlist checking
    address public immutable wm;

    constructor(address _wm) {
        wm = _wm;
    }

    /// @dev Modifier to restrict access to addresses allowed by WM
    modifier onlyAllowed() {
        WMLib.requireAllowed(wm);
        _;
    }
}
