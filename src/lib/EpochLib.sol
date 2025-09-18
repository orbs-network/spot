// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Epoch management library
/// @notice Manages time-bucket controls for TWAP order execution cadence
library EpochLib {
    error InvalidEpoch();

    function update(mapping(bytes32 => uint256) storage epochs, bytes32 hash, uint256 epoch)
        internal
        returns (uint256)
    {
        uint256 current = epoch == 0 ? 0 : (block.timestamp + (uint256(hash) % epoch)) / epoch;
        if (current < epochs[hash]) revert InvalidEpoch();
        epochs[hash] = current + 1;
        return current;
    }
}
