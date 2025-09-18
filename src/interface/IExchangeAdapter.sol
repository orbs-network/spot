// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";

interface IExchangeAdapter {
    function delegateSwap(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x)
        external;
}
