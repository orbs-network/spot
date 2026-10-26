// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPermit2 {
    struct Approval {
        address token;
        address spender;
        uint160 amount;
        uint48 expiration;
    }

    uint256 public approveCallCount;
    Approval public lastApproval;
    mapping(address owner => mapping(address token => mapping(address spender => Approval))) public allowance;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        lastApproval = Approval(token, spender, amount, expiration);
        allowance[msg.sender][token][spender] = lastApproval;
        approveCallCount++;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        Approval storage approval = allowance[from][token][msg.sender];
        require(block.timestamp <= approval.expiration, "Permit2: allowance expired");
        require(amount <= approval.amount, "Permit2: insufficient allowance");
        if (approval.amount != type(uint160).max) approval.amount -= amount;

        SafeERC20.safeTransferFrom(IERC20(token), from, to, amount);
    }
}
