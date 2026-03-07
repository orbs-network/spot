// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWrappedNative} from "src/interface/IWrappedNative.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {RePermit} from "src/RePermit.sol";
import {RePermitLib} from "src/lib/RePermitLib.sol";
import {TokenLib} from "src/lib/TokenLib.sol";

/// @title Settler
/// @notice Pulls output from solver liquidity and pays solver with input tokens.
/// @dev `x.target` is the solver address and `x.data` encodes `(uint256 outputAmount, bytes solverSig)`.
///      This contract must be called directly so the solver permit spender is always `Settler`.
/// TODO:
/// 1. Make this ownable and initialize WETH outside the constructor so CREATE2 stays stable across chains.
/// 2. Solve the remaining RePermit spender issue.
/// 3. Bind universal or other adapter routing into the signed order somehow, possibly through a delegating adapter.
/// 4. Decouple solver permits from the swapper nonce/orderHash so identical TWAP chunks can be signed and filled repeatedly.
/// 5. Give solver quotes their own expiry instead of forcing the swapper order deadline.
/// 6. Decide whether solver liquidity should stay order-specific or support generic standing quotes / batched fills.
contract Settler is ReentrancyGuard {
    error InvalidTarget();

    address public immutable repermit;
    address public immutable wrappedNative;

    constructor(address _repermit, address _wrappedNative) {
        repermit = _repermit;
        wrappedNative = _wrappedNative;
    }

    function swap(CosignedOrder memory co, Execution memory x) external nonReentrant {
        if (x.target == address(0)) revert InvalidTarget();

        // Security: always derive the witness from the forwarded order payload.
        bytes32 orderHash = OrderLib.hash(co.order);
        (uint256 outputAmount, bytes memory solverSig) = abi.decode(x.data, (uint256, bytes));

        TokenLib.transferFrom(co.order.input.token, msg.sender, x.target, co.order.input.amount);

        RePermit(repermit)
            .repermitWitnessTransferFrom(
                RePermitLib.RePermitTransferFrom(
                    RePermitLib.TokenPermissions(
                        co.order.output.token == address(0) ? wrappedNative : co.order.output.token, outputAmount
                    ),
                    co.order.nonce,
                    co.order.deadline
                ),
                RePermitLib.TransferRequest(address(this), outputAmount),
                x.target,
                orderHash,
                OrderLib.WITNESS_TYPE_SUFFIX,
                solverSig
            );

        if (co.order.output.token == address(0)) {
            IWrappedNative(wrappedNative).withdraw(outputAmount);
            TokenLib.transfer(address(0), msg.sender, outputAmount);
            return;
        }

        TokenLib.transfer(co.order.output.token, msg.sender, outputAmount);
    }

    receive() external payable {}
}
