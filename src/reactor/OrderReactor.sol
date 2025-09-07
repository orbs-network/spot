// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {IValidationCallback} from "src/interface/IValidationCallback.sol";
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
    event Fill(bytes32 indexed hash, address indexed executor, address indexed swapper, uint256 epoch);

    address public immutable cosigner;
    address public immutable repermit;

    // order hash => next epoch
    mapping(bytes32 => uint256) public epochs;

    constructor(address _repermit, address _cosigner) {
        cosigner = _cosigner;
        repermit = _repermit;
    }

    /// @notice Execute a CosignedOrder with callback
    /// @param co The cosigned order to execute
    /// @param x The execution parameters for the order
    function executeWithCallback(
        OrderLib.CosignedOrder calldata co,
        SettlementLib.Execution calldata x
    ) external payable nonReentrant {
        // Validate and resolve the order
        bytes32 hash = OrderLib.hash(co.order);
        OrderValidationLib.validate(co.order);
        CosignatureLib.validate(co, cosigner, address(repermit));
        
        // Call additional validation if specified
        if (co.order.info.additionalValidationContract != address(0)) {
            IValidationCallback(co.order.info.additionalValidationContract).validate(msg.sender, co);
        }
        
        uint256 currentEpoch = EpochLib.update(epochs, hash, co.order.epoch);

        uint256 resolvedAmountOut = ResolutionLib.resolve(co);

        // Transfer input tokens via RePermit
        _transferInput(co, hash);

        // Call the executor callback with the cosigned order and hash
        IReactorCallback(msg.sender).reactorCallback(hash, co, x);

        // Transfer output tokens and refund ETH
        _transferOutput(co, resolvedAmountOut);

        emit Fill(hash, msg.sender, co.order.info.swapper, currentEpoch);
    }

    /// @notice Transfer output tokens to recipient and refund remaining ETH to executor
    /// @param co The cosigned order containing output details
    /// @param resolvedAmountOut The resolved output amount to transfer
    function _transferOutput(OrderLib.CosignedOrder calldata co, uint256 resolvedAmountOut) private {
        // Transfer output tokens to recipient
        TokenLib.transfer(co.order.output.token, co.order.output.recipient, resolvedAmountOut);

        // Refund any remaining ETH to the executor
        TokenLib.transfer(address(0), msg.sender, address(this).balance);
    }

    /// @notice Handle input token transfers via RePermit
    /// @param co The cosigned order containing input details
    /// @param hash The hash of the order for witness verification
    function _transferInput(OrderLib.CosignedOrder calldata co, bytes32 hash) private {
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(
                    address(co.order.input.token), co.order.input.maxAmount
                ),
                co.order.info.nonce,
                co.order.info.deadline
            ),
            RePermitLib.TransferRequest(msg.sender, co.order.input.amount),
            co.order.info.swapper,
            hash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            co.signature
        );
    }

    receive() external payable {
        // Receive native asset to support native output
    }
}
