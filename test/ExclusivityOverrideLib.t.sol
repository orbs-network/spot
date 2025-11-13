// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {ExclusivityOverrideLib} from "src/lib/ExclusivityOverrideLib.sol";

// Helper contract to properly test msg.sender context
contract ExclusivityCaller {
    function applyOutput(uint256 minOut, address exclusiveExecutor, uint32 exclusivityBps)
        external
        view
        returns (uint256)
    {
        return ExclusivityOverrideLib.applyOutput(minOut, exclusiveExecutor, exclusivityBps);
    }
}

contract ExclusivityLibTest is BaseTest {
    ExclusivityCaller public caller;

    function setUp() public override {
        super.setUp();
        caller = new ExclusivityCaller();
    }

    function test_applyOutput_noChangeWhenExclusive() public {
        address addr1 = makeAddr("addr1");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 500;

        hoax(addr1);
        uint256 result = caller.applyOutput(minOut, addr1, exclusivityBps);
        // When caller is the exclusive executor, should return minOut unchanged
        assertEq(result, 1000);
    }

    function test_applyOutput_increasesWhenNotExclusive() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 500;

        hoax(addr2);
        uint256 result = caller.applyOutput(minOut, addr1, exclusivityBps);
        // 500 bps => +5% => 1000 * 1.05 = 1050
        assertEq(result, 1050);
    }

    function test_applyOutput_reverts_when_nonExclusive_sender_and_zero_bps() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        uint256 minOut = 1000;
        uint32 exclusivityBps = 0;

        hoax(addr2);
        vm.expectRevert(ExclusivityOverrideLib.InvalidSender.selector);
        caller.applyOutput(minOut, addr1, exclusivityBps);
    }
}
