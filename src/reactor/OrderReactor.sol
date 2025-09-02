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
import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {BaseReactor} from "src/lib/uniswapx/reactors/BaseReactor.sol";

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
        returns (ResolvedOrder memory resolvedOrder)
    {
        OrderLib.CosignedOrder memory cosigned = abi.decode(signedOrder.order, (OrderLib.CosignedOrder));
        bytes32 orderHash = OrderLib.hash(cosigned.order);

        OrderValidationLib.validate(cosigned.order);
        CosignatureLib.validate(cosigned, cosigner, address(repermit));

        EpochLib.update(epochs, orderHash, cosigned.order.epoch);

        uint256 outAmount = ResolutionLib.resolveOutAmount(cosigned);
        outAmount = ExclusivityOverrideLib.applyOverride(outAmount, cosigned.order.executor, cosigned.order.exclusivity);
        resolvedOrder = _resolveStruct(cosigned, outAmount, orderHash);
    }

    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(address(order.input.token), order.input.maxAmount),
                order.info.nonce,
                order.info.deadline
            ),
            RePermitLib.TransferRequest(to, order.input.amount),
            order.info.swapper,
            order.hash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            order.sig
        );
    }

    function _resolveStruct(OrderLib.CosignedOrder memory cosigned, uint256 outAmount, bytes32 orderHash)
        private
        pure
        returns (ResolvedOrder memory resolvedOrder)
    {
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
        resolvedOrder.outputs[0] = OutputToken(cosigned.order.output.token, outAmount, cosigned.order.output.recipient);
        resolvedOrder.sig = cosigned.signature;
        resolvedOrder.hash = orderHash;
    }
}
