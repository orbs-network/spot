// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";

interface IExchangeAdapter {
    function swap(OrderLib.CosignedOrder memory cosignedOrder, bytes calldata data) external;
}
