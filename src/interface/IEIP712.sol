// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title EIP-712 domain separator interface
/// @notice Provides typed data hashing functionality for signature verification
interface IEIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function hashTypedData(bytes32 structHash) external view returns (bytes32 digest);
}
