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

    function prepareFor(address token, address spenderOrRecipient, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            transfer(token, spenderOrRecipient, amount);
        } else {
            uint256 allowance = IERC20(token).allowance(address(this), spenderOrRecipient);
            IERC20(token).safeApprove(spenderOrRecipient, 0);
            IERC20(token).safeApprove(spenderOrRecipient, allowance + amount);
        }
    }
}

