// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {SignedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";

/// @notice Minimal reactor logic for settling off-chain signed orders
/// @dev Simplified version that processes single orders without arrays
abstract contract BaseReactor is IReactor, ReentrancyGuard {
    /// @notice Event emitted when an order is filled
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);

    /// @inheritdoc IReactor
    function executeWithCallback(SignedOrder calldata signedOrder, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        // Decode once and pass CosignedOrder throughout
        OrderLib.CosignedOrder memory cosignedOrder = abi.decode(signedOrder.order, (OrderLib.CosignedOrder));

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
    function _prepare(OrderLib.CosignedOrder memory cosignedOrder, bytes32 orderHash) internal virtual;

    /// @notice Fill the order by handling output transfers
    /// @param cosignedOrder The cosigned order
    /// @param resolvedAmountOut The resolved output amount
    /// @param orderHash The hash of the order
    function _fill(OrderLib.CosignedOrder memory cosignedOrder, uint256 resolvedAmountOut, bytes32 orderHash) internal virtual;

    receive() external payable {
        // Receive native asset to support native output
    }
}
