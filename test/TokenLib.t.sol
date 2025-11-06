// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {TokenLib} from "src/lib/TokenLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TokenLibHarness {
    function transferFrom(address token, address from, address to, uint256 amount) external {
        TokenLib.transferFrom(token, from, to, amount);
    }

    function prepareFor(address token, address spenderOrRecipient, uint256 amount) external {
        TokenLib.prepareFor(token, spenderOrRecipient, amount);
    }

    function approve(address token, address spender, uint256 amount) external {
        ERC20Mock(token).approve(spender, amount);
    }
}

contract TokenLibTest is Test {
    TokenLibHarness internal harness;
    ERC20Mock internal token;
    address internal from = makeAddr("from");
    address internal to = makeAddr("to");

    function setUp() public {
        harness = new TokenLibHarness();
        token = new ERC20Mock();
    }

    function test_transferFrom_zero_amount_noop() public {
        token.mint(from, 1 ether);
        vm.prank(from);
        token.approve(address(harness), 1 ether);

        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        harness.transferFrom(address(token), from, to, 0);

        assertEq(token.balanceOf(from), fromBefore, "from balance should stay");
        assertEq(token.balanceOf(to), toBefore, "to balance should stay");
    }

    function test_prepareFor_zero_amount_noop() public {
        token.mint(address(harness), 1 ether);
        vm.prank(address(harness));
        token.approve(to, 123);

        uint256 allowanceBefore = token.allowance(address(harness), to);

        harness.prepareFor(address(token), to, 0);

        assertEq(token.allowance(address(harness), to), allowanceBefore, "allowance unchanged");
        assertEq(token.balanceOf(to), 0, "no tokens moved");
    }
}
