// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

/// @notice Minimal Multicall3-style helper that executes sequential calls from calldata.
library Multicall3Lib {
    error Multicall3CallFailed(uint256 index, bytes returnData);

    function aggregate3(IMulticall3.Call3[] calldata calls) internal returns (IMulticall3.Result[] memory results) {
        uint256 length = calls.length;
        results = new IMulticall3.Result[](length);
        for (uint256 i = 0; i < length; ++i) {
            IMulticall3.Call3 calldata calli = calls[i];
            (bool success, bytes memory returnData) = calli.target.call(calli.callData);
            if (!success && !calli.allowFailure) revert Multicall3CallFailed(i, returnData);
            results[i] = IMulticall3.Result({success: success, returnData: returnData});
        }
    }
}
