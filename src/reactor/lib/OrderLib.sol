// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RePermitLib} from "src/repermit/RePermitLib.sol";

library OrderLib {
    string internal constant INPUT_TYPE = "Input(address token,uint256 amount,uint256 maxAmount)";
    bytes32 internal constant INPUT_TYPE_HASH = keccak256(bytes(INPUT_TYPE));

    string internal constant OUTPUT_TYPE = "Output(address token,uint256 amount,uint256 maxAmount,address recipient)";
    bytes32 internal constant OUTPUT_TYPE_HASH = keccak256(bytes(OUTPUT_TYPE));

    string internal constant EXCHANGE_TYPE = "Exchange(address adapter,bytes data,address ref,uint32 share)";
    bytes32 internal constant EXCHANGE_TYPE_HASH = keccak256(bytes(EXCHANGE_TYPE));

    string internal constant ORDER_TYPE =
        "Order(address reactor,Exchange exchange,Input input,Output output,address executor,address swapper,uint256 nonce,uint256 deadline,uint32 exclusivity,uint32 epoch,uint32 slippage,uint32 freshness)";
    bytes32 internal constant ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(ORDER_TYPE, EXCHANGE_TYPE, INPUT_TYPE, OUTPUT_TYPE));

    string internal constant WITNESS_TYPE_SUFFIX = string(
        abi.encodePacked(
            "Order witness)", EXCHANGE_TYPE, INPUT_TYPE, ORDER_TYPE, OUTPUT_TYPE, RePermitLib.TOKEN_PERMISSIONS_TYPE
        )
    );

    string internal constant COSIGNED_VALUE_TYPE = "CosignedValue(address token,uint256 value,uint8 decimals)";
    bytes32 internal constant COSIGNED_VALUE_TYPE_HASH = keccak256(bytes(COSIGNED_VALUE_TYPE));

    string internal constant COSIGNATURE_TYPE =
        "Cosignature(uint256 timestamp,address reactor,CosignedValue input,CosignedValue output)";
    bytes32 internal constant COSIGNATURE_TYPE_HASH = keccak256(abi.encodePacked(COSIGNATURE_TYPE, COSIGNED_VALUE_TYPE));

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
        bytes data;
        address ref;
        uint32 share; // bps, for referrer
    }

    struct Order {
        address reactor;
        Exchange exchange;
        Input input;
        Output output;
        address executor;
        address swapper;
        uint256 nonce;
        uint256 deadline;
        uint32 exclusivity;
        uint32 epoch; // seconds per chunk; 0 = single-use
        uint32 slippage; // bps
        uint32 freshness; // seconds, must be > 0
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

    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.reactor,
                hash(order.exchange),
                order.executor,
                order.swapper,
                order.nonce,
                order.deadline,
                order.exclusivity,
                order.epoch,
                order.slippage,
                order.freshness,
                hash(order.input),
                hash(order.output)
            )
        );
    }

    function hash(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TYPE_HASH, input.token, input.amount, input.maxAmount));
    }

    function hash(Output memory output) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPUT_TYPE_HASH, output.token, output.amount, output.maxAmount, output.recipient));
    }

    function hash(Exchange memory exchange) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(EXCHANGE_TYPE_HASH, exchange.adapter, keccak256(exchange.data), exchange.ref, exchange.share)
        );
    }

    function hash(Cosignature memory cosignature) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COSIGNATURE_TYPE_HASH,
                cosignature.timestamp,
                cosignature.reactor,
                keccak256(abi.encode(COSIGNED_VALUE_TYPE_HASH, cosignature.input)),
                keccak256(abi.encode(COSIGNED_VALUE_TYPE_HASH, cosignature.output))
            )
        );
    }
}
