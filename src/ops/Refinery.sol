// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IWM} from "src/interface/IWM.sol";
import {WMAllowed} from "src/lib/WMAllowed.sol";
import {Constants} from "src/reactor/Constants.sol";
import {TokenLib} from "src/lib/TokenLib.sol";
import {Multicall3Lib} from "src/lib/Multicall3Lib.sol";

/// @title Operations utility contract
/// @notice Provides operations for batching calls and sweeping token balances by basis points
contract Refinery is WMAllowed {
    event Refined(address indexed token, address indexed recipient, uint256 amount);

    constructor(address _wm) WMAllowed(_wm) {}

    function execute(IMulticall3.Call3[] calldata calls) external onlyAllowed returns (IMulticall3.Result[] memory) {
        return Multicall3Lib.aggregate3(calls);
    }

    function transfer(address token, address recipient, uint256 bps) external onlyAllowed {
        uint256 bal = TokenLib.balanceOf(token);
        uint256 amount = Math.mulDiv(bal, bps, Constants.BPS);
        TokenLib.transfer(token, recipient, amount);
        if (amount > 0) emit Refined(token, recipient, amount);
    }

    receive() external payable {
        // accept ETH
    }
}
