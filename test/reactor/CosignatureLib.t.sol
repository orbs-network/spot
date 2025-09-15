// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";

import {CosignatureLib} from "src/reactor/lib/CosignatureLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";
import {RePermit} from "src/repermit/RePermit.sol";

contract CosignatureLibTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.warp(1 days);
    }

    function callValidateCosignature(CosignedOrder memory co, address cosigner) external view {
        CosignatureLib.validate(co, cosigner, repermit);
    }

    // No per-test builders: set BaseTest vars in each test where needed

    function test_validateCosignature_ok() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_stale() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        vm.warp(1 days + 400); // freshness=300 from build time
        vm.expectRevert(CosignatureLib.StaleCosignature.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidInputToken() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.input.token = makeAddr("wrongIn");
        vm.expectRevert(CosignatureLib.InvalidCosignatureInputToken.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidOutputToken() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.output.token = makeAddr("wrongOut");
        vm.expectRevert(CosignatureLib.InvalidCosignatureOutputToken.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_zeroInputValue() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.input.value = 0;
        vm.expectRevert(CosignatureLib.InvalidCosignatureZeroInputValue.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_zeroOutputValue() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.output.value = 0;
        vm.expectRevert(CosignatureLib.InvalidCosignatureZeroOutputValue.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidCosigner() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        vm.expectRevert(CosignatureLib.InvalidCosignatureSigner.selector);
        this.callValidateCosignature(co, other);
    }

    function test_validateCosignature_reverts_invalidReactor() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.reactor = makeAddr("wrongReactor");
        vm.expectRevert(CosignatureLib.InvalidCosignatureReactor.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_futureTimestamp() public {
        freshness = 300;
        inAmount = 1_000;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.timestamp = 1 days + 1; // future vs warped base
        vm.expectRevert(CosignatureLib.FutureCosignatureTimestamp.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_freshness_zero() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.order.freshness = 0;
        vm.expectRevert(CosignatureLib.InvalidFreshness.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_freshness_vs_epoch() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.order.epoch = 60;
        co.order.freshness = 60; // >= epoch
        vm.expectRevert(CosignatureLib.InvalidFreshnessVsEpoch.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidChainid() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;
        CosignedOrder memory co = order();
        co = cosign(co);
        co.cosignatureData.chainid = 999; // Wrong chainid
        vm.expectRevert(CosignatureLib.InvalidCosignatureChainid.selector);
        this.callValidateCosignature(co, signer);
    }
}
