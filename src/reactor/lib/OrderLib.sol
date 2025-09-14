// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RePermitLib} from "src/repermit/RePermitLib.sol";
import {
    OrderInfo,
    Input,
    Output,
    Exchange,
    Order,
    CosignedValue,
    Cosignature,
    CosignedOrder
} from "src/reactor/lib/OrderStructs.sol";

library OrderLib {
    string internal constant ORDER_INFO_TYPE =
        "OrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline,address additionalValidationContract,bytes additionalValidationData)";
    bytes32 internal constant ORDER_INFO_TYPE_HASH = keccak256(bytes(ORDER_INFO_TYPE));

    string internal constant INPUT_TYPE = "Input(address token,uint256 amount,uint256 maxAmount)";
    bytes32 internal constant INPUT_TYPE_HASH = keccak256(bytes(INPUT_TYPE));

    string internal constant OUTPUT_TYPE = "Output(address token,uint256 amount,uint256 maxAmount,address recipient)";
    bytes32 internal constant OUTPUT_TYPE_HASH = keccak256(bytes(OUTPUT_TYPE));

    string internal constant EXCHANGE_TYPE = "Exchange(address adapter,address ref,uint32 share)";
    bytes32 internal constant EXCHANGE_TYPE_HASH = keccak256(bytes(EXCHANGE_TYPE));

    string internal constant ORDER_TYPE =
        "Order(OrderInfo info,address executor,Exchange exchange,uint32 exclusivity,uint32 epoch,uint32 slippage,uint32 freshness,Input input,Output output)";
    bytes32 internal constant ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(ORDER_TYPE, INPUT_TYPE, ORDER_INFO_TYPE, OUTPUT_TYPE, EXCHANGE_TYPE));

    string internal constant WITNESS_TYPE_SUFFIX = string(
        abi.encodePacked(
            "Order witness)",
            EXCHANGE_TYPE,
            INPUT_TYPE,
            ORDER_TYPE,
            ORDER_INFO_TYPE,
            OUTPUT_TYPE,
            RePermitLib.TOKEN_PERMISSIONS_TYPE
        )
    );

    string internal constant COSIGNED_VALUE_TYPE = "CosignedValue(address token,uint256 value,uint8 decimals)";
    bytes32 internal constant COSIGNED_VALUE_TYPE_HASH = keccak256(bytes(COSIGNED_VALUE_TYPE));

    string internal constant COSIGNATURE_TYPE =
        "Cosignature(uint256 timestamp,address reactor,CosignedValue input,CosignedValue output)";
    bytes32 internal constant COSIGNATURE_TYPE_HASH = keccak256(abi.encodePacked(COSIGNATURE_TYPE, COSIGNED_VALUE_TYPE));

    function hash(OrderInfo memory info) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_INFO_TYPE_HASH,
                info.reactor,
                info.swapper,
                info.nonce,
                info.deadline,
                info.additionalValidationContract,
                keccak256(info.additionalValidationData)
            )
        );
    }

    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                hash(order.info),
                order.executor,
                hash(order.exchange),
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
        return keccak256(abi.encode(EXCHANGE_TYPE_HASH, exchange.adapter, exchange.ref, exchange.share));
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
