// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";

// Helper contract to properly test msg.sender context
contract ResolutionCaller {
    function resolve(OrderLib.CosignedOrder memory co) external view returns (uint256) {
        return ResolutionLib.resolve(co);
    }
}

contract ExclusivityLibTest is Test {
    ResolutionCaller public caller;

    function setUp() public {
        caller = new ResolutionCaller();
    }

    function _createCosigned(address executor, uint32 exclusivityBps)
        internal
        returns (OrderLib.CosignedOrder memory co)
    {
        OrderLib.Order memory o;
        o.swapper = makeAddr("swapper");
        o.input.token = makeAddr("in");
        o.input.amount = 1_000;
        o.input.maxAmount = 2_000;
        o.output.token = makeAddr("out");
        o.output.amount = 1_000; // Base amount for easier calculation
        o.output.maxAmount = 10_000;
        o.slippage = 0; // No slippage for easier testing
        o.executor = executor;
        o.exclusivity = exclusivityBps;

        co.order = o;
        // Set cosignature data such that cosignedOutput = input.amount (1:1 ratio)
        co.cosignatureData.input = OrderLib.CosignedValue({token: o.input.token, value: 100, decimals: 18});
        co.cosignatureData.output = OrderLib.CosignedValue({token: o.output.token, value: 100, decimals: 18});
    }

    function test_applyOverride_noChangeWhenExclusive() public {
        address addr1 = makeAddr("addr1");
        OrderLib.CosignedOrder memory co = _createCosigned(addr1, 500);

        vm.prank(addr1);
        uint256 result = caller.resolve(co);
        // Should be max(1000 (base output), 1000 (cosigned output)) = 1000 with no override
        assertEq(result, 1000);
    }

    function test_applyOverride_increasesWhenNotExclusive() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        OrderLib.CosignedOrder memory co = _createCosigned(addr1, 500);

        vm.prank(addr2);
        uint256 result = caller.resolve(co);
        // 500 bps => +5% => 1000 * 1.05 = 1050
        assertEq(result, 1050);
    }

    function test_applyOverride_reverts_when_nonExclusive_sender_and_zero_bps() public {
        address addr1 = makeAddr("addr1");
        address addr2 = makeAddr("addr2");
        OrderLib.CosignedOrder memory co = _createCosigned(addr1, 0);

        vm.prank(addr2);
        vm.expectRevert(ResolutionLib.InvalidSender.selector);
        caller.resolve(co);
    }
}
