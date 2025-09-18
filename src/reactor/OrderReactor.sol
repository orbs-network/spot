// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {OrderLib} from "src/libs/OrderLib.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {TokenLib} from "src/libs/TokenLib.sol";
import {SettlementLib} from "src/libs/SettlementLib.sol";

import {RePermit} from "src/repermit/RePermit.sol";
import {RePermitLib} from "src/libs/RePermitLib.sol";
import {OrderValidationLib} from "src/libs/OrderValidationLib.sol";
import {CosignatureLib} from "src/libs/CosignatureLib.sol";
import {EpochLib} from "src/libs/EpochLib.sol";
import {ResolutionLib} from "src/libs/ResolutionLib.sol";
import {ExclusivityOverrideLib} from "src/libs/ExclusivityOverrideLib.sol";

/// @title OrderReactor
/// @notice Verifies and settles cosigned orders via an executor callback.
contract OrderReactor is ReentrancyGuard {
    /// @dev Emitted after a successful fill.
    event Fill(bytes32 indexed hash, address indexed executor, address indexed swapper, uint256 epoch);

    address public immutable cosigner;
    address public immutable repermit;

    // order hash => next epoch
    mapping(bytes32 => uint256) public epochs;

    constructor(address _repermit, address _cosigner) {
        cosigner = _cosigner;
        repermit = _repermit;
    }

    /// @notice Execute a cosigned order and invoke the executor callback for swap/settlement.
    /// @param co Cosigned order payload.
    /// @param x Execution parameters (minOut, fee, adapter data).
    function executeWithCallback(CosignedOrder calldata co, Execution calldata x) external payable nonReentrant {
        bytes32 hash = OrderLib.hash(co.order);
        OrderValidationLib.validate(co.order);
        CosignatureLib.validate(co, cosigner, repermit);

        uint256 currentEpoch = EpochLib.update(epochs, hash, co.order.epoch);

        uint256 resolvedAmountOut = ExclusivityOverrideLib.applyExclusivityOverride(
            ResolutionLib.resolve(co), co.order.executor, co.order.exclusivity
        );

        _transferInput(co, hash);

        IReactorCallback(msg.sender).reactorCallback(hash, resolvedAmountOut, co, x);

        _transferOutput(co, resolvedAmountOut);

        emit Fill(hash, msg.sender, co.order.swapper, currentEpoch);
    }

    /// @dev Finalize settlement by transferring resolved outputs to the recipient and refunding any ETH.
    function _transferOutput(CosignedOrder calldata co, uint256 resolvedAmountOut) private {
        TokenLib.transferFrom(co.order.output.token, msg.sender, co.order.output.recipient, resolvedAmountOut);
        TokenLib.transfer(address(0), msg.sender, address(this).balance);
    }

    /// @dev Pull input tokens from the swapper via RePermit witness-bound permit.
    function _transferInput(CosignedOrder calldata co, bytes32 hash) private {
        RePermit(address(repermit)).repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom(
                RePermitLib.TokenPermissions(address(co.order.input.token), co.order.input.maxAmount),
                co.order.nonce,
                co.order.deadline
            ),
            RePermitLib.TransferRequest(msg.sender, co.order.input.amount),
            co.order.swapper,
            hash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            co.signature
        );
    }

    receive() external payable {
        // Receive native asset to support native output
    }
}
