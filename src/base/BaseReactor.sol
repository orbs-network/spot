// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

/// @notice Minimal reactor logic for settling off-chain signed orders
/// @dev Simplified version that processes CosignedOrders directly
abstract contract BaseReactor is ReentrancyGuard {
    /// @notice Event emitted when an order is filled
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);

    /// @notice Execute a cosigned order with callback data
    /// @param cosignedOrder The cosigned order to execute
    function executeWithCallback(OrderLib.CosignedOrder calldata cosignedOrder, bytes calldata /* callbackData */)
        external
        payable
        nonReentrant
    {
        // Resolve the order and get the essential parameters
        (uint256 resolvedAmountOut, bytes32 orderHash) = _resolve(cosignedOrder);

        // Prepare for order execution (validate and transfer input tokens)
        _prepare(cosignedOrder, orderHash);

        // Fill the order (handle output transfers)
        _fill(cosignedOrder, resolvedAmountOut, orderHash);
    }

    /// @notice Resolve order-specific requirements and return essential parameters
    /// @param cosignedOrder The cosigned order to resolve
    /// @return resolvedAmountOut The resolved output amount
    /// @return orderHash The hash of the order
    function _resolve(OrderLib.CosignedOrder memory cosignedOrder)
        internal
        virtual
        returns (uint256 resolvedAmountOut, bytes32 orderHash);

    /// @notice Validate and transfer input tokens in preparation for order fill
    /// @param cosignedOrder The cosigned order
    /// @param orderHash The hash of the order
    function _prepare(OrderLib.CosignedOrder memory cosignedOrder, bytes32 orderHash) internal virtual {
        // Default implementation handles input token transfers
        // Can be overridden by concrete implementations
        _handleInputTokens(cosignedOrder, orderHash);
    }

    /// @notice Handle input token transfers - to be implemented by concrete reactors
    /// @param cosignedOrder The cosigned order
    /// @param orderHash The hash of the order
    function _handleInputTokens(OrderLib.CosignedOrder memory cosignedOrder, bytes32 orderHash) internal virtual;

    /// @notice Fill the order by handling output transfers
    /// @param cosignedOrder The cosigned order
    /// @param resolvedAmountOut The resolved output amount
    /// @param orderHash The hash of the order
    function _fill(OrderLib.CosignedOrder memory cosignedOrder, uint256 resolvedAmountOut, bytes32 orderHash) internal virtual {
        // Transfer output token to recipient
        TokenLib.transfer(cosignedOrder.order.output.token, cosignedOrder.order.output.recipient, resolvedAmountOut);

        emit Fill(orderHash, msg.sender, cosignedOrder.order.info.swapper, cosignedOrder.order.info.nonce);

        // Refund any remaining ETH to the filler
        if (address(this).balance > 0) {
            TokenLib.transfer(address(0), msg.sender, address(this).balance);
        }
    }

    receive() external payable {
        // Receive native asset to support native output
    }
}
