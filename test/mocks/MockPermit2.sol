// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

contract MockPermit2 {
    struct Approval {
        address token;
        address spender;
        uint160 amount;
        uint48 expiration;
    }

    uint256 public approveCallCount;
    Approval public lastApproval;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        lastApproval = Approval(token, spender, amount, expiration);
        approveCallCount++;
    }
}
