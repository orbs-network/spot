// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {
    IValidationCallback,
    ResolvedOrder,
    SignedOrder,
    InputToken,
    OutputToken,
    OrderInfo
} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {BaseReactor} from "src/base/BaseReactor.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

import {RePermit} from "src/repermit/RePermit.sol";
import {RePermitLib} from "src/repermit/RePermitLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {CosignatureLib} from "src/reactor/lib/CosignatureLib.sol";
import {EpochLib} from "src/reactor/lib/EpochLib.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";
import {ExclusivityOverrideLib} from "src/lib/uniswapx/lib/ExclusivityOverrideLib.sol";

contract OrderReactor is BaseReactor {
    address public immutable cosigner;
    address public immutable repermit;

    // order hash => next epoch
    mapping(bytes32 => uint256) public epochs;

    constructor(address _repermit, address _cosigner) {
        cosigner = _cosigner;
        repermit = _repermit;
    }

    function _resolve(SignedOrder calldata signedOrder)
        internal
        override
        returns (uint256 resolvedAmountOut, bytes32 orderHash)
    {
        OrderLib.CosignedOrder memory cosigned = abi.decode(signedOrder.order, (OrderLib.CosignedOrder));
        orderHash = OrderLib.hash(cosigned.order);

        OrderValidationLib.validate(cosigned.order);
        CosignatureLib.validate(cosigned, cosigner, address(repermit));

        EpochLib.update(epochs, orderHash, cosigned.order.epoch);

        uint256 outAmount = ResolutionLib.resolveOutAmount(cosigned);
        resolvedAmountOut =
            ExclusivityOverrideLib.applyOverride(outAmount, cosigned.order.executor, cosigned.order.exclusivity);
    }

    function _prepare(SignedOrder calldata order, bytes32 orderHash) internal override {
        OrderLib.CosignedOrder memory cosigned = abi.decode(order.order, (OrderLib.CosignedOrder));

        // Transfer input tokens via RePermit
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(address(cosigned.order.input.token), cosigned.order.input.maxAmount),
                cosigned.order.info.nonce,
                cosigned.order.info.deadline
            ),
            RePermitLib.TransferRequest(msg.sender, cosigned.order.input.amount),
            cosigned.order.info.swapper,
            orderHash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            cosigned.signature
        );
    }

    function _fill(SignedOrder calldata order, uint256 resolvedAmountOut, bytes32 orderHash) internal override {
        OrderLib.CosignedOrder memory cosigned = abi.decode(order.order, (OrderLib.CosignedOrder));

        // Transfer output token to recipient
        TokenLib.transfer(cosigned.order.output.token, cosigned.order.output.recipient, resolvedAmountOut);

        emit Fill(orderHash, msg.sender, cosigned.order.info.swapper, cosigned.order.info.nonce);

        // Refund any remaining ETH to the filler
        if (address(this).balance > 0) {
            TokenLib.transfer(address(0), msg.sender, address(this).balance);
        }
    }

    function _createResolvedOrder(SignedOrder calldata order, uint256 resolvedAmountOut, bytes32 orderHash)
        internal
        pure
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        OrderLib.CosignedOrder memory cosigned = abi.decode(order.order, (OrderLib.CosignedOrder));

        resolvedOrder.info = OrderInfo(
            cosigned.order.info.reactor,
            cosigned.order.info.swapper,
            cosigned.order.info.nonce,
            cosigned.order.info.deadline,
            IValidationCallback(cosigned.order.info.additionalValidationContract),
            cosigned.order.info.additionalValidationData
        );
        resolvedOrder.input =
            InputToken(cosigned.order.input.token, cosigned.order.input.amount, cosigned.order.input.maxAmount);
        resolvedOrder.outputs = new OutputToken[](1);
        resolvedOrder.outputs[0] =
            OutputToken(cosigned.order.output.token, resolvedAmountOut, cosigned.order.output.recipient);
        resolvedOrder.sig = cosigned.signature;
        resolvedOrder.hash = orderHash;
    }
}
