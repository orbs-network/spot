// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ResolvedOrder} from "src/interface/ReactorStructs.sol";

interface IExchangeAdapter {
    function swap(ResolvedOrder memory order, bytes calldata data) external;
}
