// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";

contract ExclusivityLibTest is Test {
    function _apply(uint256 base, address exec, uint32 bps) external view returns (uint256) {
        return ResolutionLib.applyExclusivityOverride(base, exec, bps);
    }

    function test_applyOverride_noChangeWhenExclusive() public {
        address addr1 = makeAddr("addr1");
        vm.prank(addr1);
        assertEq(this._apply(1000, addr1, 500), 1000);
    }

    function test_applyOverride_increasesWhenNotExclusive() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        vm.prank(addr2);
        // 500 bps => +5%
        assertEq(this._apply(1000, addr1, 500), 1050);
    }

    function test_applyOverride_reverts_when_nonExclusive_sender_and_zero_bps() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        vm.prank(addr2);
        vm.expectRevert(ResolutionLib.InvalidSender.selector);
        this._apply(1000, addr1, 0);
    }
}
