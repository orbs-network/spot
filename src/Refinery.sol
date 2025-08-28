// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {IWM} from "src/interface/IWM.sol";
import {Constants} from "src/reactor/Constants.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

contract Refinery {
    address public immutable multicall;
    address public immutable wm;

    error NotAllowed();

    event Refined(address indexed token, address indexed recipient, uint256 amount);

    modifier onlyAllowed() {
        if (!IWM(wm).allowed(msg.sender)) revert NotAllowed();
        _;
    }

    constructor(address _multicall, address _wm) {
        multicall = _multicall;
        wm = _wm;
    }

    function execute(IMulticall3.Call3[] calldata calls) external onlyAllowed returns (bytes memory) {
        return Address.functionDelegateCall(multicall, abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls));
    }

    function transfer(address token, address recipient, uint256 bps) external onlyAllowed {
        uint256 bal = TokenLib.balanceOf(token);
        uint256 amount = bal * bps / Constants.BPS;
        TokenLib.transfer(token, recipient, amount);
        if (amount > 0) emit Refined(token, recipient, amount);
    }

    receive() external payable {
        // accept ETH
    }
}
