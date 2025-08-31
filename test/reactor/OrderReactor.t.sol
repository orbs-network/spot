// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";
import {OrderReactor} from "src/reactor/OrderReactor.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SignedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {RePermit} from "src/repermit/RePermit.sol";

contract OrderReactorTest is BaseTest {
    OrderReactor public reactor;
    address public cosigner;
    uint256 public cosignerPK;

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);

        (cosigner, cosignerPK) = makeAddrAndKey("cosigner");
        reactor = new OrderReactor(repermit, cosigner);

        allowThis();
    }

    function test_strictExclusivity_reverts_wrong_executor() public {
        address wrongExecutor = makeAddr("wrongExecutor");

        // Create an order with different executor
        OrderLib.CosignedOrder memory co = _createCosignedOrder(wrongExecutor);
        SignedOrder memory so = _signedOrderFrom(co);

        // Should revert since msg.sender (this) doesn't match executor (wrongExecutor)
        vm.expectRevert(OrderReactor.StrictExclusivityViolation.selector);
        reactor.execute(so);
    }

    function _createCosignedOrder(address executor) internal view returns (OrderLib.CosignedOrder memory co) {
        OrderLib.Order memory o;
        o.info.reactor = address(reactor);
        o.info.swapper = signer;
        o.info.nonce = 1;
        o.info.deadline = 1_086_400;
        o.info.additionalValidationContract = address(0);
        o.info.additionalValidationData = abi.encode(address(0), uint16(0));
        o.epoch = 0;
        o.slippage = 0;
        o.freshness = 300;
        o.executor = executor;
        o.input = OrderLib.Input({token: address(token), amount: 100, maxAmount: 100});
        o.output = OrderLib.Output({token: address(token), amount: 200, maxAmount: 200, recipient: signer});

        co.order = o;
        co.signature = hex""; // Empty signature for test

        // Create cosignature data
        OrderLib.Cosignature memory c;
        c.timestamp = 1_000_000;
        c.input = OrderLib.CosignedValue({token: o.input.token, value: 100, decimals: 18});
        c.output = OrderLib.CosignedValue({token: o.output.token, value: 200, decimals: 18});
        co.cosignatureData = c;
        co.cosignature = _signCosignature(c);
    }

    function _signCosignature(OrderLib.Cosignature memory c) internal view returns (bytes memory sig) {
        bytes32 digest = RePermit(repermit).hashTypedData(OrderLib.hash(c));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPK, digest);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function _signedOrderFrom(OrderLib.CosignedOrder memory co) internal pure returns (SignedOrder memory so) {
        so.order = abi.encode(co);
        so.sig = hex""; // Empty signature for test
    }
}
