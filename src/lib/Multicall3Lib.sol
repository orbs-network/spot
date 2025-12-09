// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

/// @title Multicall3 library
/// @notice Minimal Multicall3-style helper that executes sequential calls from calldata
library Multicall3Lib {
    error Multicall3CallFailed(uint256 index, bytes returnData);

    /// @notice Executes a batch of call3Value payloads sequentially and forwards per-call msg.value.
    /// @param calls Array of Multicall3 call structs including value to forward to each target.
    /// @return results Array of Multicall3 result structs mirroring each call's success flag and returndata.
    function aggregate3Value(IMulticall3.Call3Value[] calldata calls)
        internal
        returns (IMulticall3.Result[] memory results)
    {
        results = new IMulticall3.Result[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            IMulticall3.Call3Value calldata calli = calls[i];
            (bool success, bytes memory returnData) = calli.target.call{value: calli.value}(calli.callData);
            if (!success && !calli.allowFailure) revert Multicall3CallFailed(i, returnData);
            results[i] = IMulticall3.Result({success: success, returnData: returnData});
        }
    }
}
