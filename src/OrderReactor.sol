// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {IWM} from "src/interface/IWM.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {WMAllowed} from "src/lib/WMAllowed.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {TokenLib} from "src/lib/TokenLib.sol";
import {SettlementLib} from "src/lib/SettlementLib.sol";

import {RePermit} from "src/RePermit.sol";
import {RePermitLib} from "src/lib/RePermitLib.sol";
import {OrderValidationLib} from "src/lib/OrderValidationLib.sol";
import {CosignatureLib} from "src/lib/CosignatureLib.sol";
import {EpochLib} from "src/lib/EpochLib.sol";
import {ResolutionLib} from "src/lib/ResolutionLib.sol";
import {ExclusivityOverrideLib} from "src/lib/ExclusivityOverrideLib.sol";

/// @title OrderReactor
/// @notice Verifies and settles cosigned orders via an executor callback.
/// @dev Supports emergency pause functionality controlled by WM allowlist.
contract OrderReactor is ReentrancyGuard, Pausable, WMAllowed {
    /// @dev Emitted after a successful fill.
    event Fill(bytes32 indexed hash, address indexed executor, address indexed swapper, uint256 epoch);

    address public immutable cosigner;
    address public immutable repermit;

    // order hash => next epoch
    mapping(bytes32 => uint256) public epochs;

    constructor(address _repermit, address _cosigner, address _wm) WMAllowed(_wm) {
        cosigner = _cosigner;
        repermit = _repermit;
    }

    /// @notice Pause the reactor to prevent order execution.
    /// @dev Only addresses allowed by WM can pause.
    function pause() external onlyAllowed {
        _pause();
    }

    /// @notice Unpause the reactor to allow order execution.
    /// @dev Only addresses allowed by WM can unpause.
    function unpause() external onlyAllowed {
        _unpause();
    }

    /// @notice Execute a cosigned order and invoke the executor callback for swap/settlement.
    /// @param co Cosigned order payload.
    /// @param x Execution parameters (minOut, fee, adapter data).
    function executeWithCallback(CosignedOrder calldata co, Execution calldata x)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        bytes32 hash = OrderLib.hash(co.order);
        OrderValidationLib.validate(co.order);
        CosignatureLib.validate(co, cosigner, repermit);

        uint256 currentEpoch = EpochLib.update(epochs, hash, co.order.epoch);

        // Core amount resolution: compute minimum output considering market price, slippage, and exclusivity
        // 1. ResolutionLib.resolve() computes base minOut from cosigned price with slippage protection
        // 2. ExclusivityOverrideLib.applyExclusivityOverride() applies exclusivity penalties for non-exclusive executors
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
        RePermit(address(repermit))
            .repermitWitnessTransferFrom(
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
