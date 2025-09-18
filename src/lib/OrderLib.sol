// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RePermitLib} from "src/lib/RePermitLib.sol";
import {Input, Output, Exchange, Order, CosignedValue, Cosignature, CosignedOrder} from "src/Structs.sol";

/// @title Order hashing library
/// @notice EIP-712 structured data hashing for orders and cosignatures
library OrderLib {
    string internal constant INPUT_TYPE = "Input(address token,uint256 amount,uint256 maxAmount)";
    bytes32 internal constant INPUT_TYPE_HASH = keccak256(bytes(INPUT_TYPE));

    string internal constant OUTPUT_TYPE = "Output(address token,uint256 amount,uint256 maxAmount,address recipient)";
    bytes32 internal constant OUTPUT_TYPE_HASH = keccak256(bytes(OUTPUT_TYPE));

    string internal constant EXCHANGE_TYPE = "Exchange(address adapter,address ref,uint32 share,bytes data)";
    bytes32 internal constant EXCHANGE_TYPE_HASH = keccak256(bytes(EXCHANGE_TYPE));

    string internal constant ORDER_TYPE =
        "Order(address reactor,address executor,Exchange exchange,address swapper,uint256 nonce,uint256 deadline,uint256 chainid,uint32 exclusivity,uint32 epoch,uint32 slippage,uint32 freshness,Input input,Output output)";
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
        "Cosignature(address cosigner,address reactor,uint256 chainid,uint256 timestamp,CosignedValue input,CosignedValue output)";
    bytes32 internal constant COSIGNATURE_TYPE_HASH = keccak256(abi.encodePacked(COSIGNATURE_TYPE, COSIGNED_VALUE_TYPE));

    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.reactor,
                order.executor,
                hash(order.exchange),
                order.swapper,
                order.nonce,
                order.deadline,
                order.chainid,
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
        return keccak256(abi.encode(INPUT_TYPE_HASH, input));
    }

    function hash(Output memory output) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPUT_TYPE_HASH, output));
    }

    function hash(Exchange memory exchange) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(EXCHANGE_TYPE_HASH, exchange.adapter, exchange.ref, exchange.share, keccak256(exchange.data))
        );
    }

    function hash(Cosignature memory cosignature) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COSIGNATURE_TYPE_HASH,
                cosignature.cosigner,
                cosignature.reactor,
                cosignature.chainid,
                cosignature.timestamp,
                keccak256(abi.encode(COSIGNED_VALUE_TYPE_HASH, cosignature.input)),
                keccak256(abi.encode(COSIGNED_VALUE_TYPE_HASH, cosignature.output))
            )
        );
    }
}
