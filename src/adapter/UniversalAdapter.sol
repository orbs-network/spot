// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

/// @title UniversalAdapter
/// @notice Dispatches fill execution to a selected adapter using fill-time routing data.
contract UniversalAdapter is IExchangeAdapter {
    /// @inheritdoc IExchangeAdapter
    function delegateSwap(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x)
        external
        override
    {
        if (x.target == address(0)) revert InvalidTarget();

        Execution memory inner = abi.decode(x.data, (Execution));
        Address.functionDelegateCall(
            x.target, abi.encodeWithSelector(IExchangeAdapter.delegateSwap.selector, hash, resolvedAmountOut, co, inner)
        );
    }
}
