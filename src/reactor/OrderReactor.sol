// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {ResolvedOrder, OrderInfo, InputToken, OutputToken} from "src/interface/CallbackStructs.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

import {RePermit} from "src/repermit/RePermit.sol";
import {RePermitLib} from "src/repermit/RePermitLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {CosignatureLib} from "src/reactor/lib/CosignatureLib.sol";
import {EpochLib} from "src/reactor/lib/EpochLib.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";
import {ExclusivityLib} from "src/reactor/lib/ExclusivityLib.sol";

contract OrderReactor is ReentrancyGuard {
    /// @notice Event emitted when an order is filled
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 epoch);

    address public immutable cosigner;
    address public immutable repermit;

    // order hash => next epoch
    mapping(bytes32 => uint256) public epochs;

    constructor(address _repermit, address _cosigner) {
        cosigner = _cosigner;
        repermit = _repermit;
    }

    /// @notice Execute a CosignedOrder with callback
    /// @param cosignedOrder The cosigned order to execute
    /// @param callbackData Data to pass to the callback
    function executeWithCallback(OrderLib.CosignedOrder calldata cosignedOrder, bytes calldata callbackData)
        external
        payable
        nonReentrant
    {
        // Validate and resolve the order
        bytes32 orderHash = OrderLib.hash(cosignedOrder.order);
        OrderValidationLib.validate(cosignedOrder.order);
        CosignatureLib.validate(cosignedOrder, cosigner, address(repermit));
        uint256 currentEpoch = EpochLib.update(epochs, orderHash, cosignedOrder.order.epoch);

        uint256 outAmount = ResolutionLib.resolveOutAmount(cosignedOrder);
        uint256 resolvedAmountOut = ExclusivityLib.applyOverride(
            outAmount, cosignedOrder.order.executor, cosignedOrder.order.exclusivity
        );

        // Transfer input tokens via RePermit
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(
                    address(cosignedOrder.order.input.token), cosignedOrder.order.input.maxAmount
                ),
                cosignedOrder.order.info.nonce,
                cosignedOrder.order.info.deadline
            ),
            RePermitLib.TransferRequest(msg.sender, cosignedOrder.order.input.amount),
            cosignedOrder.order.info.swapper,
            orderHash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            cosignedOrder.signature
        );

        // Create ResolvedOrder for callback
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({
            token: cosignedOrder.order.output.token,
            amount: resolvedAmountOut,
            recipient: cosignedOrder.order.output.recipient
        });

        resolvedOrders[0] = ResolvedOrder({
            info: OrderInfo({
                reactor: address(this),
                swapper: cosignedOrder.order.info.swapper,
                nonce: cosignedOrder.order.info.nonce,
                deadline: cosignedOrder.order.info.deadline,
                additionalValidationContract: cosignedOrder.order.info.additionalValidationContract,
                additionalValidationData: cosignedOrder.order.info.additionalValidationData
            }),
            input: InputToken({
                token: cosignedOrder.order.input.token,
                amount: cosignedOrder.order.input.amount,
                maxAmount: cosignedOrder.order.input.maxAmount
            }),
            outputs: outputs,
            sig: cosignedOrder.signature,
            hash: orderHash
        });

        // Call the executor callback
        IReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);

        // Transfer output tokens to recipient
        TokenLib.transfer(cosignedOrder.order.output.token, cosignedOrder.order.output.recipient, resolvedAmountOut);

        emit Fill(orderHash, msg.sender, cosignedOrder.order.info.swapper, currentEpoch);

        // Refund any remaining ETH to the filler
        TokenLib.transfer(address(0), msg.sender, address(this).balance);
    }

    receive() external payable {
        // Receive native asset to support native output
    }
}
