// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BaseReactor} from "src/base/BaseReactor.sol";
import {SignedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";

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

    /// @notice Execute a SignedOrder (compatibility wrapper)
    /// @param signedOrder The signed order containing encoded CosignedOrder  
    function executeWithCallback(SignedOrder calldata signedOrder, bytes calldata /* callbackData */)
        external
        payable
        nonReentrant
    {
        // Decode SignedOrder to CosignedOrder and execute directly
        OrderLib.CosignedOrder memory cosignedOrder = abi.decode(signedOrder.order, (OrderLib.CosignedOrder));
        
        // Resolve the order and get the essential parameters
        (uint256 resolvedAmountOut, bytes32 orderHash) = _resolve(cosignedOrder);

        // Prepare for order execution (validate and transfer input tokens)
        _prepare(cosignedOrder, orderHash);

        // Fill the order (handle output transfers)
        _fill(cosignedOrder, resolvedAmountOut, orderHash);
    }

    function _resolve(OrderLib.CosignedOrder memory cosignedOrder)
        internal
        override
        returns (uint256 resolvedAmountOut, bytes32 orderHash)
    {
        orderHash = OrderLib.hash(cosignedOrder.order);

        OrderValidationLib.validate(cosignedOrder.order);
        CosignatureLib.validate(cosignedOrder, cosigner, address(repermit));

        EpochLib.update(epochs, orderHash, cosignedOrder.order.epoch);

        uint256 outAmount = ResolutionLib.resolveOutAmount(cosignedOrder);
        resolvedAmountOut =
            ExclusivityOverrideLib.applyOverride(outAmount, cosignedOrder.order.executor, cosignedOrder.order.exclusivity);
    }

    function _handleInputTokens(OrderLib.CosignedOrder memory cosignedOrder, bytes32 orderHash) internal override {
        // Transfer input tokens via RePermit
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(address(cosignedOrder.order.input.token), cosignedOrder.order.input.maxAmount),
                cosignedOrder.order.info.nonce,
                cosignedOrder.order.info.deadline
            ),
            RePermitLib.TransferRequest(msg.sender, cosignedOrder.order.input.amount),
            cosignedOrder.order.info.swapper,
            orderHash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            cosignedOrder.signature
        );
    }
}
