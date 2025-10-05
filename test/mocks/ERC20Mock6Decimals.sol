// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @notice ERC20 mock token that reports 6 decimals to emulate USD-denominated stablecoins
contract ERC20Mock6Decimals is ERC20Mock {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
