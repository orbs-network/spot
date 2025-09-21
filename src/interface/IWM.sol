// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Allowlist management interface
/// @notice Interface for checking if addresses are allowed to perform operations
interface IWM {
    function allowed(address) external view returns (bool);
}
