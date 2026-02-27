// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title Core data structures for the Spot DeFi protocol
/// @notice Defines orders, cosignatures, and execution parameters for limit orders, TWAP, and stop-loss functionality

/// @dev tokens that need to be sent from the swapper in order to satisfy an order
struct Input {
    address token;
    uint256 amount; // chunk
    uint256 maxAmount; // total
}

/// @dev tokens that need to be received by the recipient in order to satisfy an order
struct Output {
    address token;
    uint256 limit; // minimum acceptable output to recipient
    uint256 triggerLower; // lower trigger boundary (stop-loss style)
    uint256 triggerUpper; // upper trigger boundary (take-profit style)
    address recipient;
}

struct Exchange {
    address adapter;
    address ref;
    uint32 share; // bps, for referrer
    bytes data;
}

struct Order {
    address reactor;
    address executor;
    Exchange exchange;
    address swapper;
    uint256 nonce;
    uint256 start; // order cannot execute before this timestamp
    uint256 deadline;
    uint256 chainid;
    uint32 exclusivity;
    uint32 epoch; // seconds per chunk; 0 = single-use
    uint32 slippage; // bps
    uint32 freshness; // seconds, must be > 0
    Input input;
    Output output;
}

struct CosignedValue {
    address token;
    uint256 value; // in 18 decimals
    uint8 decimals; // token decimals
}

struct Cosignature {
    address cosigner;
    address reactor;
    uint256 chainid;
    uint256 timestamp;
    CosignedValue input;
    CosignedValue output;
}

struct CosignedOrder {
    Order order;
    bytes signature;
    Cosignature trigger;
    Cosignature current;
    bytes triggerCosignature;
    bytes currentCosignature;
}

/// @dev Parameters provided by the executor for a fill
struct Execution {
    uint256 minAmountOut; // minimum acceptable output to recipient after slippage and fees
    Output[] fees; // individual fee payments to distribute during settlement
    address target; // target contract selected by the executor for adapter-level routing
    bytes data;
}
