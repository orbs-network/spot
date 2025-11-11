// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Allowlist management contract
/// @notice Two-step ownership allowlist manager for executors and admin functions
contract WM is Ownable2Step {
    mapping(address => bool) public allowed;

    event AllowedSet(address indexed addr, bool allowed);

    constructor(address _owner) Ownable(_owner) {
        allowed[_owner] = true;
    }

    function set(address[] calldata addr, bool _allowed) external onlyOwner {
        for (uint256 i; i < addr.length; i++) {
            allowed[addr[i]] = _allowed;
            emit AllowedSet(addr[i], _allowed);
        }
    }
}
