// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockTokenTransferProxy {
    event Pulled(address indexed token, address indexed from, address indexed to, uint256 amount);

    function pull(address token, address from, address to, uint256 amount) external {
        IERC20(token).transferFrom(from, to, amount);
        emit Pulled(token, from, to, amount);
    }
}

contract MockParaswapAugustus {
    MockTokenTransferProxy public immutable tokenTransferProxy;
    bool public shouldFail;

    constructor(MockTokenTransferProxy _tokenTransferProxy) {
        tokenTransferProxy = _tokenTransferProxy;
    }

    function setShouldFail(bool value) external {
        shouldFail = value;
    }

    function doSwap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address to) external {
        if (shouldFail) revert("Mock ParaSwap swap failed");

        tokenTransferProxy.pull(tokenIn, msg.sender, address(this), amountIn);
        ERC20Mock(tokenOut).mint(to, amountOut);
    }

    function getTokenTransferProxy() external view returns (address) {
        return address(tokenTransferProxy);
    }
}
