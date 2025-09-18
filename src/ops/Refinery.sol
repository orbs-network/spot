// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {IWM} from "src/interface/IWM.sol";
import {Constants} from "src/reactor/Constants.sol";
import {TokenLib} from "src/libs/TokenLib.sol";
import {Multicall3Lib} from "src/libs/Multicall3Lib.sol";

contract Refinery {
    address public immutable wm;

    error NotAllowed();

    event Refined(address indexed token, address indexed recipient, uint256 amount);

    modifier onlyAllowed() {
        if (!IWM(wm).allowed(msg.sender)) revert NotAllowed();
        _;
    }

    constructor(address _wm) {
        wm = _wm;
    }

    function execute(IMulticall3.Call3[] calldata calls) external onlyAllowed returns (IMulticall3.Result[] memory) {
        return Multicall3Lib.aggregate3(calls);
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
