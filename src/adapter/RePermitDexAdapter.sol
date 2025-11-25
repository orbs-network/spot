// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {RePermit} from "src/RePermit.sol";
import {RePermitLib} from "src/lib/RePermitLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RePermit exchange adapter
/// @notice Adapter for RFQ swaps settled via RePermit transfer
contract RePermitDexAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

    RePermit public immutable repermit;
    address public immutable owner;

    /// @param _repermit The RePermit contract address
    /// @param _owner The address of the market maker (signer)
    constructor(address _repermit, address _owner) {
        repermit = RePermit(_repermit);
        owner = _owner;
    }

    /// @inheritdoc IExchangeAdapter
    function delegateSwap(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x)
        external
        override
    {
        // Decode the signature from execution data
        bytes memory signature = abi.decode(x.data, (bytes));
        address signer = owner;

        // Transfer input tokens to the market maker (signer)
        // Note: Input tokens are already in this contract (Executor)
        IERC20(co.order.input.token).safeTransfer(signer, co.order.input.amount);

        // Pull output tokens from the market maker to this contract
        // The witness is the user's order hash, binding the MM's fill to this specific order
        repermit.repermitWitnessTransferFrom(
            RePermitLib.RePermitTransferFrom({
                permitted: RePermitLib.TokenPermissions({token: co.order.output.token, amount: resolvedAmountOut}),
                nonce: 0,
                deadline: co.order.deadline
            }),
            RePermitLib.TransferRequest({to: address(this), amount: resolvedAmountOut}),
            signer,
            hash,
            OrderLib.WITNESS_TYPE_SUFFIX,
            signature
        );
    }
}
