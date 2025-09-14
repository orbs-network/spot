// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";

interface IExchangeAdapter {
    function swap(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, bytes calldata data) external;
}
