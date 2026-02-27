// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";

import {ResolutionLib} from "src/lib/ResolutionLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";

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
        triggerLower = 0;
        triggerUpper = 0;
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);

        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 1_980);
    }

    function test_resolveOutAmount_revert_trigger_not_hit() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        triggerLower = 1_500;
        triggerUpper = 2_500;
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        vm.expectRevert(ResolutionLib.NotTriggered.selector);
        this.callResolve(co);
    }

    function test_resolveOutAmount_revert_trigger_not_hit_with_lower_only() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        triggerLower = 1_500;
        triggerUpper = 0; // unset upper
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        vm.expectRevert(ResolutionLib.NotTriggered.selector);
        this.callResolve(co);
    }

    function test_resolveOutAmount_revert_trigger_not_hit_with_upper_only() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        triggerLower = 0; // unset lower
        triggerUpper = 2_500;
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        vm.expectRevert(ResolutionLib.NotTriggered.selector);
        this.callResolve(co);
    }

    function test_resolveOutAmount_trigger_uses_trigger_not_current() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        triggerLower = 1_500;
        triggerUpper = 2_500;
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);

        // Trigger output = 3000 (hit), current output = 2000 (drifted back in-range).
        co.trigger = Cosignature({
            cosigner: signer,
            reactor: co.order.reactor,
            chainid: block.chainid,
            timestamp: block.timestamp,
            input: CosignedValue({
                token: co.order.input.token, value: 300, decimals: _tokenDecimals(co.order.input.token)
            }),
            output: CosignedValue({
                token: co.order.output.token, value: 100, decimals: _tokenDecimals(co.order.output.token)
            })
        });
        co.current = Cosignature({
            cosigner: signer,
            reactor: co.order.reactor,
            chainid: block.chainid,
            timestamp: block.timestamp,
            input: CosignedValue({
                token: co.order.input.token, value: 200, decimals: _tokenDecimals(co.order.input.token)
            }),
            output: CosignedValue({
                token: co.order.output.token, value: 100, decimals: _tokenDecimals(co.order.output.token)
            })
        });
        co.triggerCosignature = signEIP712(repermit, signerPK, OrderLib.hash(co.trigger));
        co.currentCosignature = signEIP712(repermit, signerPK, OrderLib.hash(co.current));

        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 1_980);
    }

    function test_resolveOutAmount_trigger_boundary_values_pass() public {
        executor = address(this);
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 1_200;
        triggerLower = 2_000; // boundary equals trigger output
        triggerUpper = 5_000;
        cosignInValue = 200;
        cosignOutValue = 100;
        CosignedOrder memory co = order();
        co = cosign(co);
        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 1_980);
    }

    function test_resolveOutAmount_handles_decimals_beyond_eighteen() public {
        executor = address(this);
        inAmount = 1_000_000_000_000; // 1e12 units
        inMax = inAmount;
        outAmount = 0;
        triggerUpper = 0;
        cosignInValue = 3;
        cosignOutValue = 2;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.current.input.decimals = 24;
        co.current.output.decimals = 6;

        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, 0);
    }
}
