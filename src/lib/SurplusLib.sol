// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Constants} from "src/reactor/Constants.sol";
import {TokenLib} from "src/lib/TokenLib.sol";

/// @title Surplus distribution library
/// @notice Distributes token surpluses between referrers and swappers based on BPS shares
library SurplusLib {
    event Surplus(address indexed ref, address swapper, address token, uint256 amount, uint256 refshare);

    /// @dev Distributes surplus tokens between referrer and swapper based on referrer share
    /// 1. Get total balance of specified token held by this contract
    /// 2. Calculate referrer share as (total * shareBps) / BPS
    /// 3. Transfer referrer share to ref address (if non-zero)
    /// 4. Transfer remaining balance to swapper
    /// 5. Emit surplus event if any tokens were distributed
    function distribute(address ref, address swapper, address token, uint32 shareBps) internal {
        uint256 total = TokenLib.balanceOf(token);
        if (total == 0) return;
        uint256 refshare = ref == address(0) ? 0 : (total * shareBps) / Constants.BPS;
        TokenLib.transfer(token, ref, refshare);
        TokenLib.transfer(token, swapper, total - refshare);
        emit Surplus(ref, swapper, token, total, refshare);
    }
}
