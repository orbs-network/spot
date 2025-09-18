// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TokenLib {
    using SafeERC20 for IERC20;

    function transfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) Address.sendValue(payable(to), amount);
        else IERC20(token).safeTransfer(to, amount);
    }

    function balanceOf(address token) internal view returns (uint256) {
        return token == address(0) ? address(payable(address(this))).balance : IERC20(token).balanceOf(address(this));
    }

    function transferFrom(address token, address from, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
        }
    }

    function prepareFor(address token, address spenderOrRecipient, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            transfer(token, spenderOrRecipient, amount);
        } else {
            // Set exact allowance using forceApprove to support tokens that
            // revert on non-zero -> non-zero approvals (e.g., USDT-like).
            IERC20(token).forceApprove(spenderOrRecipient, amount);
        }
    }
}
