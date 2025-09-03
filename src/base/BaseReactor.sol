// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SignedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {IReactorCallback} from "src/lib/uniswapx/interfaces/IReactorCallback.sol";
import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";

/// @notice Minimal reactor logic for settling off-chain signed orders
/// @dev Simplified version that processes single orders without arrays
abstract contract BaseReactor is IReactor, ReentrancyGuard {
    /// @notice Event emitted when an order is filled
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);

    /// @inheritdoc IReactor
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        // Resolve the order and get the essential parameters
        (uint256 resolvedAmountOut, bytes32 orderHash) = _resolve(order);

        // Prepare for order execution (validate and transfer input tokens)
        _prepare(order, orderHash);

        // Execute the callback - convert to array format for backward compatibility
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = _createResolvedOrder(order, resolvedAmountOut, orderHash);
        IReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);

        // Fill the order (handle output transfers)
        _fill(order, resolvedAmountOut, orderHash);
    }

    /// @notice Resolve order-specific requirements and return essential parameters
    /// @param order The signed order to resolve
    /// @return resolvedAmountOut The resolved output amount
    /// @return orderHash The hash of the order
    function _resolve(SignedOrder calldata order)
        internal
        virtual
        returns (uint256 resolvedAmountOut, bytes32 orderHash);

    /// @notice Validate and transfer input tokens in preparation for order fill
    /// @param order The signed order
    /// @param orderHash The hash of the order
    function _prepare(SignedOrder calldata order, bytes32 orderHash) internal virtual;

    /// @notice Fill the order by handling output transfers
    /// @param order The signed order
    /// @param resolvedAmountOut The resolved output amount
    /// @param orderHash The hash of the order
    function _fill(SignedOrder calldata order, uint256 resolvedAmountOut, bytes32 orderHash) internal virtual;

    /// @notice Create a ResolvedOrder struct for backward compatibility
    /// @param order The signed order
    /// @param resolvedAmountOut The resolved output amount
    /// @param orderHash The hash of the order
    /// @return resolvedOrder The resolved order struct
    function _createResolvedOrder(SignedOrder calldata order, uint256 resolvedAmountOut, bytes32 orderHash)
        internal
        virtual
        returns (ResolvedOrder memory resolvedOrder);

    receive() external payable {
        // Receive native asset to support native output
    }
}

// Re-export the structs we need for compatibility
import {ResolvedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
