// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

import {RePermit} from "src/repermit/RePermit.sol";
import {RePermitLib} from "src/repermit/RePermitLib.sol";
import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {CosignatureLib} from "src/reactor/lib/CosignatureLib.sol";
import {EpochLib} from "src/reactor/lib/EpochLib.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";

contract OrderReactor is ReentrancyGuard {
    /// @notice Event emitted when an order is filled
    event Fill(bytes32 indexed orderHash, address indexed executor, address indexed swapper, uint256 epoch);

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
    /// @param execution The execution parameters for the order
    function executeWithCallback(
        OrderLib.CosignedOrder calldata cosignedOrder,
        SettlementLib.Execution calldata execution
    ) external payable nonReentrant {
        // Validate and resolve the order
        bytes32 orderHash = OrderLib.hash(cosignedOrder.order);
        OrderValidationLib.validate(cosignedOrder.order);
        CosignatureLib.validate(cosignedOrder, cosigner, address(repermit));
        uint256 currentEpoch = EpochLib.update(epochs, orderHash, cosignedOrder.order.epoch);

        uint256 outAmount = ResolutionLib.resolveOutAmount(cosignedOrder);
        uint256 resolvedAmountOut =
            ResolutionLib.applyExclusivityOverride(outAmount, cosignedOrder.order.executor, cosignedOrder.order.exclusivity);

        // Transfer input tokens via RePermit
        _transferInput(cosignedOrder, orderHash);

        // Call the executor callback with the cosigned order and hash
        IReactorCallback(msg.sender).reactorCallback(orderHash, cosignedOrder, execution);

        // Transfer output tokens and refund ETH
        _transferOutput(cosignedOrder, resolvedAmountOut);

        emit Fill(orderHash, msg.sender, cosignedOrder.order.info.swapper, currentEpoch);
    }

    /// @notice Transfer output tokens to recipient and refund remaining ETH to executor
    /// @param cosignedOrder The cosigned order containing output details
    /// @param resolvedAmountOut The resolved output amount to transfer
    function _transferOutput(OrderLib.CosignedOrder calldata cosignedOrder, uint256 resolvedAmountOut) private {
        // Transfer output tokens to recipient
        TokenLib.transfer(cosignedOrder.order.output.token, cosignedOrder.order.output.recipient, resolvedAmountOut);

        // Refund any remaining ETH to the executor
        TokenLib.transfer(address(0), msg.sender, address(this).balance);
    }

    /// @notice Handle input token transfers via RePermit
    /// @param cosignedOrder The cosigned order containing input details
    /// @param orderHash The hash of the order for witness verification
    function _transferInput(OrderLib.CosignedOrder calldata cosignedOrder, bytes32 orderHash) private {
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
    }

    receive() external payable {
        // Receive native asset to support native output
    }
}
