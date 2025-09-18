// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Epoch management library
/// @notice Manages time-bucket controls for TWAP order execution cadence
library EpochLib {
    error InvalidEpoch();

    /// @dev Updates the epoch state for TWAP order execution timing
    /// 1. For single-use orders (epoch=0), always returns 0 and blocks future executions
    /// 2. For TWAP orders, calculates current time bucket using hash-based staggering
    /// 3. Prevents execution if current bucket hasn't advanced since last execution
    /// 4. Updates stored epoch to next bucket and returns current bucket number
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
