// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @dev tokens that need to be sent from the swapper in order to satisfy an order
struct Input {
    address token;
    uint256 amount; // chunk
    uint256 maxAmount; // total
}

/// @dev tokens that need to be received by the recipient in order to satisfy an order
struct Output {
    address token;
    uint256 amount; // limit
    uint256 maxAmount; // trigger; max uint256 = no trigger
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
    uint256 deadline;
    uint32 exclusivity;
    uint32 epoch; // seconds per chunk; 0 = single-use
    uint32 slippage; // bps
    uint32 freshness; // seconds, must be > 0
    Input input;
    Output output;
}

struct CosignedValue {
    address token;
    uint256 value; // in token decimals
    uint8 decimals; // informative
}

struct Cosignature {
    uint256 timestamp;
    address reactor;
    CosignedValue input;
    CosignedValue output;
}

struct CosignedOrder {
    Order order;
    bytes signature;
    Cosignature cosignatureData;
    bytes cosignature;
}

/// @dev Parameters provided by the executor for a fill
struct Execution {
    uint256 minAmountOut;
    Output fee;
    bytes data;
}
