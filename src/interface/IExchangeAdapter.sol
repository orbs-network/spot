// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {CosignedOrder, Execution} from "src/Structs.sol";

/// @title Exchange adapter interface
/// @notice Interface for swap execution adapters that handle DEX interactions
interface IExchangeAdapter {
    error InvalidTarget();

    function delegateSwap(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x) external;
}
