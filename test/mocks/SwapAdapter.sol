// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrderLib} from "src/reactor/lib/OrderLib.sol";
// no-op adapter for tests

contract SwapAdapterMock {
    error InvalidOrder();

    function swap(OrderLib.CosignedOrder memory cosignedOrder, bytes calldata) external {
        // No validation needed - this is a mock adapter for tests
        // no-op; Executor handles settlement
    }
}
