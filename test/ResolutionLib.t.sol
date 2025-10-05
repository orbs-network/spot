// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";

import {ResolutionLib} from "src/lib/ResolutionLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
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
        cosignInValue = 200;
        cosignOutValue = 100;
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
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.order.output.stop = 1_500; // cosignedOutput is 2000 > 1500
        vm.expectRevert(ResolutionLib.CosignedExceedsStop.selector);
        this.callResolve(co);
    }

    function test_resolveOutAmount_stop_zero_treated_as_max() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        outMax = 0; // stop=0 should be treated as type(uint256).max
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        // cosignedOutput is 2000, but stop=0 should not revert
        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 1_980);
    }

    function test_resolveOutAmount_stop_zero_never_reverts() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        outMax = 0; // stop=0 should be treated as type(uint256).max
        cosignInValue = 1;
        cosignOutValue = type(uint256).max / 1_000; // Very high output value
        CosignedOrder memory co = order();
        co = cosign(co);
        // Even with extremely high cosignedOutput, stop=0 should not revert
        uint256 outAmt = this.callResolve(co);
        // Result should be valid (no revert)
        assertGt(outAmt, 0);
    }

    function test_resolveOutAmount_handles_decimals_beyond_eighteen() public {
        executor = address(this);
        inAmount = 1_000_000_000_000; // 1e12 units
        inMax = inAmount;
        outAmount = 0;
        outMax = type(uint256).max;
        cosignInValue = 3;
        cosignOutValue = 2;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.input.decimals = 24;
        co.cosignatureData.output.decimals = 6;

        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 0);
    }
}
