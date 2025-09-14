// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @dev generic order information
///  should be included as the first field in any concrete order types
struct OrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the swapper
    // signature commits to the specific reactor that they trust to fill their order properly
    address reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by swapper
    address swapper;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid
    uint256 deadline;
    // Custom validation contract
    address additionalValidationContract;
    // Encoded validation params for additionalValidationContract
    bytes additionalValidationData;
}

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
}

struct Order {
    OrderInfo info;
    address executor;
    Exchange exchange;
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
