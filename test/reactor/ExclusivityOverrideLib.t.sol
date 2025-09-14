// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";
import {ExclusivityOverrideLib} from "src/reactor/lib/ExclusivityOverrideLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

// Helper contract to properly test msg.sender context
contract ResolutionCaller {
    function resolve(OrderLib.CosignedOrder memory co) external view returns (uint256) {
        uint256 outAmount = ResolutionLib.resolve(co);
        return ExclusivityOverrideLib.applyExclusivityOverride(
            outAmount, co.order.executor, co.order.exclusivity
        );
    }
}

contract ExclusivityLibTest is BaseTest {
    ResolutionCaller public caller;

    function setUp() public override {
        super.setUp();
        caller = new ResolutionCaller();
    }

    // No per-test builders: set BaseTest vars and call order()/cosign() directly in tests

    function test_applyOverride_noChangeWhenExclusive() public {
        address addr1 = makeAddr("addr1");
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_000;
        outMax = 10_000;
        OrderLib.CosignedOrder memory co = order();
        co.order.executor = addr1;
        co.order.exclusivity = 500;
        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);

        vm.prank(addr1);
        uint256 result = caller.resolve(co);
        // Should be max(1000 (base output), 1000 (cosigned output)) = 1000 with no override
        assertEq(result, 1000);
    }

    function test_applyOverride_increasesWhenNotExclusive() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_000;
        outMax = 10_000;
        OrderLib.CosignedOrder memory co = order();
        co.order.executor = addr1;
        co.order.exclusivity = 500;
        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);

        vm.prank(addr2);
        uint256 result = caller.resolve(co);
        // 500 bps => +5% => 1000 * 1.05 = 1050
        assertEq(result, 1050);
    }

    function test_applyOverride_reverts_when_nonExclusive_sender_and_zero_bps() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_000;
        outMax = 10_000;
        OrderLib.CosignedOrder memory co = order();
        co.order.executor = addr1;
        co.order.exclusivity = 0;
        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);

        vm.prank(addr2);
        vm.expectRevert(ResolutionLib.InvalidSender.selector);
        caller.resolve(co);
    }
}
