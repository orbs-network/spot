// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {CosignedOrder, Execution} from "src/Structs.sol";
// no-op adapter for tests

contract SwapAdapterMock {
    error InvalidOrder();

    function delegateSwap(bytes32, uint256, CosignedOrder memory, Execution memory) external {
        // No validation needed - this is a mock adapter for tests
        // no-op; Executor handles settlement
    }
}
