// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal Permit2 interface for compatibility
/// @dev This is a simplified version of the full IPermit2 interface
///      Only includes what's needed for the Spot protocol
interface IPermit2 {
    // This interface is primarily used as a type for addresses
    // The actual RePermit contract implements the specific methods needed
}