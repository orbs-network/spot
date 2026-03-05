// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/// @title DelegatingAdapter
/// @notice Executes swap logic by delegatecalling into an arbitrary target.
contract DelegatingAdapter is IExchangeAdapter {
    /// @inheritdoc IExchangeAdapter
    function delegateSwap(
        bytes32,
        /*hash*/
        uint256,
        /*resolvedAmountOut*/
        CosignedOrder memory,
        Execution memory x
    )
        external
        override
    {
        if (x.target == address(0)) revert InvalidTarget();

        Address.functionDelegateCall(x.target, x.data);
    }
}
