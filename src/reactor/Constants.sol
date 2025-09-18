// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Protocol constants for the Spot DeFi protocol
/// @notice Defines basis points denomination and maximum slippage limits
library Constants {
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_SLIPPAGE = BPS / 2;
}
