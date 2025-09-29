// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {ExclusivityOverrideLib} from "src/lib/ExclusivityOverrideLib.sol";

// Helper contract to properly test msg.sender context
contract ExclusivityCaller {
    function applyExclusivityOverride(uint256 minOut, address exclusiveExecutor, uint32 exclusivityBps)
        external
        view
        returns (uint256)
    {
        return ExclusivityOverrideLib.applyExclusivityOverride(minOut, exclusiveExecutor, exclusivityBps);
    }
}

contract ExclusivityLibTest is BaseTest {
    ExclusivityCaller public caller;

    function setUp() public override {
        super.setUp();
        caller = new ExclusivityCaller();
    }

    function test_applyOverride_noChangeWhenExclusive() public {
        address addr1 = makeAddr("addr1");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 500;

        vm.prank(addr1);
        uint256 result = caller.applyExclusivityOverride(minOut, addr1, exclusivityBps);
        // When caller is the exclusive executor, should return minOut unchanged
        assertEq(result, 1000);
    }

    function test_applyOverride_increasesWhenNotExclusive() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 500;

        vm.prank(addr2);
        uint256 result = caller.applyExclusivityOverride(minOut, addr1, exclusivityBps);
        // 500 bps => +5% => 1000 * 1.05 = 1050
        assertEq(result, 1050);
    }

    function test_applyOverride_reverts_when_nonExclusive_sender_and_zero_bps() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 0;

        vm.prank(addr2);
        vm.expectRevert(ExclusivityOverrideLib.InvalidSender.selector);
        caller.applyExclusivityOverride(minOut, addr1, exclusivityBps);
    }
}
