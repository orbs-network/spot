// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title CommitteeSync interface
/// @notice Reads committee-backed config blobs
interface ICommitteeSync {
    function config(bytes32 key, address account) external view returns (bytes memory value);
}
