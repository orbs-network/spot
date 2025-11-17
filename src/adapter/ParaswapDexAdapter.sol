// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {IParaswapAugustus} from "src/interface/IParaswapAugustus.sol";

/**
 * @title ParaswapDexAdapter
 * @notice Exchange adapter that targets ParaSwap's AugustusSwapper contracts
 * @dev ParaSwap routes need allowances on the TokenTransferProxy, looked up from the router before every swap.
 */
contract ParaswapDexAdapter is IExchangeAdapter {
    using SafeERC20 for IERC20;

    /// @notice ParaSwap router that executes swaps (a.k.a. AugustusSwapper)
    address public immutable router;

    /// @param _router Address of the ParaSwap AugustusSwapper router
    constructor(address _router) {
        router = _router;
    }

    /// @inheritdoc IExchangeAdapter
    function delegateSwap(
        bytes32,
        /*hash*/
        uint256,
        /*resolvedAmountOut*/
        CosignedOrder memory co,
        Execution memory x
    )
        external
        override
    {
        IERC20 inputToken = IERC20(co.order.input.token);
        address tokenTransferProxy = IParaswapAugustus(router).getTokenTransferProxy();

        inputToken.forceApprove(tokenTransferProxy, co.order.input.amount);
        Address.functionCall(router, x.data);
        inputToken.forceApprove(tokenTransferProxy, 0);
    }
}
