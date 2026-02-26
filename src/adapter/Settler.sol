// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {IWrappedNative} from "src/interface/IWrappedNative.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {RePermit} from "src/RePermit.sol";
import {RePermitLib} from "src/lib/RePermitLib.sol";
import {TokenLib} from "src/lib/TokenLib.sol";

/// @title Settler
/// @notice Pulls output from solver liquidity and pays solver with input tokens.
/// @dev `x.target` is the solver address and `x.data` encodes `(uint256 outputAmount, bytes solverSig)`.
contract Settler is IExchangeAdapter {
    address public immutable repermit;
    address public immutable wrappedNative;

    constructor(address _repermit, address _wrappedNative) {
        repermit = _repermit;
        wrappedNative = _wrappedNative;
    }

    /// @inheritdoc IExchangeAdapter
    function delegateSwap(bytes32 hash, uint256, CosignedOrder memory co, Execution memory x) external override {
        if (x.target == address(0)) revert InvalidTarget();

        (uint256 outputAmount, bytes memory solverSig) = abi.decode(x.data, (uint256, bytes));

        TokenLib.transfer(co.order.input.token, x.target, co.order.input.amount);

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
                hash,
                OrderLib.WITNESS_TYPE_SUFFIX,
                solverSig
            );

        if (co.order.output.token == address(0)) {
            IWrappedNative(wrappedNative).withdraw(outputAmount);
        }
    }
}
