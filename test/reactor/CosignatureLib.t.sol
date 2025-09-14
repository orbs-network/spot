// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {CosignatureLib} from "src/reactor/lib/CosignatureLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {CosignedOrder, Order, Cosignature, CosignedValue} from "src/reactor/lib/OrderStructs.sol";
import {RePermit} from "src/repermit/RePermit.sol";

contract CosignatureLibTest is Test {
    RePermit rp;
    address signer;
    uint256 signerPK;
    address other;

    function setUp() public {
        rp = new RePermit();
        (signer, signerPK) = makeAddrAndKey("signer");
        other = makeAddr("other");
        vm.warp(1_000_000);
    }

    function callValidateCosignature(CosignedOrder memory co, address cosigner) external view {
        CosignatureLib.validate(co, cosigner, address(rp));
    }

    function _signCosignature(Cosignature memory c) internal view returns (bytes memory sig) {
        bytes32 digest = rp.hashTypedData(OrderLib.hash(c));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function _baseCosignedWithSig() internal returns (CosignedOrder memory co, bytes32 orderHash) {
        Order memory o;
        o.info.reactor = makeAddr("reactor");
        o.info.swapper = signer;
        o.input.token = makeAddr("in");
        o.input.amount = 1_000;
        o.input.maxAmount = 2_000;
        o.output.token = makeAddr("out");
        o.output.amount = 500;
        o.output.maxAmount = 5_000;
        o.slippage = 100; // 1%
        o.freshness = 300; // 5 minutes
        o.executor = makeAddr("executor");

        orderHash = OrderLib.hash(o);
        co.order = o;

        Cosignature memory c;
        c.timestamp = 1_000_000;
        c.reactor = o.info.reactor;
        c.input = CosignedValue({token: o.input.token, value: 100, decimals: 18});
        c.output = CosignedValue({token: o.output.token, value: 200, decimals: 18});
        co.cosignatureData = c;
        co.cosignature = _signCosignature(c);
    }

    function test_validateCosignature_ok() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_stale() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        vm.warp(1_000_400); // freshness=300, timestamp=1_000_000 → stale
        vm.expectRevert(CosignatureLib.StaleCosignature.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidInputToken() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.input.token = makeAddr("wrongIn");
        vm.expectRevert(CosignatureLib.InvalidCosignatureInputToken.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidOutputToken() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.output.token = makeAddr("wrongOut");
        vm.expectRevert(CosignatureLib.InvalidCosignatureOutputToken.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_zeroInputValue() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.input.value = 0;
        vm.expectRevert(CosignatureLib.InvalidCosignatureZeroInputValue.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_zeroOutputValue() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.output.value = 0;
        vm.expectRevert(CosignatureLib.InvalidCosignatureZeroOutputValue.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_invalidCosigner() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        vm.expectRevert(CosignatureLib.InvalidCosignature.selector);
        this.callValidateCosignature(co, other);
    }

    function test_validateCosignature_reverts_invalidReactor() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.reactor = makeAddr("wrongReactor");
        vm.expectRevert(CosignatureLib.InvalidCosignatureReactor.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_futureTimestamp() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.cosignatureData.timestamp = 1_000_001; // future vs warped 1_000_000
        vm.expectRevert(CosignatureLib.FutureCosignatureTimestamp.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_freshness_zero() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.order.freshness = 0;
        vm.expectRevert(CosignatureLib.InvalidFreshness.selector);
        this.callValidateCosignature(co, signer);
    }

    function test_validateCosignature_reverts_freshness_vs_epoch() public {
        (CosignedOrder memory co,) = _baseCosignedWithSig();
        co.order.epoch = 60;
        co.order.freshness = 60; // >= epoch
        vm.expectRevert(CosignatureLib.InvalidFreshnessVsEpoch.selector);
        this.callValidateCosignature(co, signer);
    }
}
