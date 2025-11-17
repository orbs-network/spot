// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Minimal interface for ParaSwap Augustus routers
interface IParaswapAugustus {
    function getTokenTransferProxy() external view returns (address);
}
