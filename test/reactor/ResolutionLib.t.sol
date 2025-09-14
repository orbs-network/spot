// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";

import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";

contract ResolutionLibTest is BaseTest {
    function callResolve(CosignedOrder memory co) external pure returns (uint256) {
        return ResolutionLib.resolve(co);
    }

    // No per-test builders; tests set BaseTest vars and use order()/cosign()

    function test_resolveOutAmount_ok() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        outMax = 10_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 1_980);
    }

    function test_resolveOutAmount_revert_cosigned_exceeds_max() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        outMax = 10_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.order.output.maxAmount = 1_500; // cosignedOutput is 2000 > 1500
        vm.expectRevert(ResolutionLib.CosignedMaxAmount.selector);
        this.callResolve(co);
    }
}
