// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
// no-op adapter for tests

contract SwapAdapterMock {
    error InvalidOrder();

    function swap(OrderLib.ResolvedOrder memory order, bytes calldata) external {
        if (order.outputs.length != 1) revert InvalidOrder();
        // no-op; Executor handles settlement
    }
}
