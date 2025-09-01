// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Constants} from "src/reactor/Constants.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";

library SurplusLib {
    event Surplus(address indexed ref, address swapper, address token, uint256 amount, uint256 refshare);

    function distribute(address ref, address swapper, address token, uint32 shareBps) internal {
        uint256 total = TokenLib.balanceOf(token);
        uint256 refshare = (total * shareBps) / Constants.BPS;
        if (refshare > 0) TokenLib.transfer(token, ref, refshare);
        TokenLib.transfer(token, swapper, total - refshare);
        if (total > 0) emit Surplus(ref, swapper, token, total, refshare);
    }
}
