// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";
import {Executor} from "src/executor/Executor.sol";
import {OrderReactor} from "src/reactor/OrderReactor.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {Execution} from "src/Structs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {RePermit} from "src/repermit/RePermit.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {CosignedOrder, Output} from "src/Structs.sol";
import {SwapAdapterMock} from "test/mocks/SwapAdapter.sol";
import {ResolutionLib} from "src/reactor/lib/ResolutionLib.sol";

contract OrderReactorE2ETest is BaseTest {
    OrderReactor public reactorUut;
    Executor public exec;
    DefaultDexAdapter public adapterUut;
    MockDexRouter public router;

    function setUp() public override {
        super.setUp();
        reactorUut = new OrderReactor(repermit, signer);
        allowThis();
        exec = new Executor(address(reactorUut), wm);
        allow(address(exec));

        router = new MockDexRouter();
        adapterUut = new DefaultDexAdapter(address(router));

        reactor = address(reactorUut);
        executor = address(exec);
        adapter = address(adapterUut);
        recipient = signer;
        slippage = 0;
        freshness = 300;
    }

    function test_e2e_erc20_end_to_end_minOut_delta_and_pull_from_executor() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;

        CosignedOrder memory co = order();

        fundOrderInput(co);

        ERC20Mock(address(token2)).mint(address(exec), 600 ether);

        cosignInValue = 1000;
        cosignOutValue = 600;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = Execution({
            minAmountOut: 600 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0, address(exec))
        });

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);

        assertEq(ERC20Mock(outToken).balanceOf(recipient), before + 600 ether);
        assertEq(ERC20Mock(outToken).allowance(address(exec), address(reactorUut)), 0);
    }

    function test_e2e_eth_end_to_end_minOut_delta_and_refund() public {
        inToken = address(token);
        outToken = address(0);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 1 ether;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());
        CosignedOrder memory co = order();

        fundOrderInput(co);

        vm.deal(address(exec), 1 ether);

        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = Execution({
            minAmountOut: 1 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });

        uint256 before = recipient.balance;
        exec.execute(co, ex);
        assertEq(recipient.balance - before, 1 ether);
        assertEq(address(reactorUut).balance, 0);
    }

    function test_e2e_twap_multi_fill_respects_epoch_and_permit_limits() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 1 ether;
        inMax = 2 ether;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        freshness = 20;

        CosignedOrder memory co = order();
        uint32 epochSeconds = 30;
        co.order.epoch = epochSeconds;
        co.order.input.maxAmount = inMax;

        cosignInValue = 1_000;
        cosignOutValue = 600;
        co = cosign(co);
        bytes32 orderHash = OrderLib.hash(co.order);
        bytes32 permitDigest = permitDigestFor(co, address(reactorUut));
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        Execution memory ex = Execution({
            minAmountOut: 500 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(
                MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 500 ether, address(exec)
            )
        });

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);
        assertEq(ERC20Mock(outToken).balanceOf(recipient) - before, 500 ether);
        assertEq(RePermit(repermit).spent(signer, permitDigest), inAmount);

        uint256 nextEpoch = reactorUut.epochs(orderHash);
        uint256 offset = uint256(orderHash) % uint256(epochSeconds);
        uint256 warpTarget = nextEpoch * uint256(epochSeconds);
        if (warpTarget > offset) {
            warpTarget -= offset;
        } else {
            warpTarget = block.timestamp + epochSeconds;
        }
        vm.warp(warpTarget + 1);

        co = cosign(co);
        exec.execute(co, ex);
        assertEq(ERC20Mock(outToken).balanceOf(recipient) - before, 1_000 ether);
        assertEq(RePermit(repermit).spent(signer, permitDigest), inAmount * 2);
    }

    function test_e2e_stop_loss_respects_max_output_trigger() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 0.5 ether;
        outMax = 0.55 ether;

        CosignedOrder memory co = order();

        fundOrderInput(co);

        cosignInValue = 1 ether;
        cosignOutValue = 0.7 ether;
        co = cosign(co);

        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = Execution({
            minAmountOut: 0.5 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(
                MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0.5 ether, address(exec)
            )
        });

        vm.expectRevert(ResolutionLib.CosignedMaxAmount.selector);
        exec.execute(co, ex);

        cosignOutValue = 0.5 ether;
        vm.warp(block.timestamp + 1);
        co = cosign(co);

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);
        assertEq(ERC20Mock(outToken).balanceOf(recipient) - before, 0.5 ether);
    }

    function test_e2e_exclusivity_override_enforces_competitor_min_out() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = inAmount;
        outAmount = 100;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());

        CosignedOrder memory co = order();
        co.order.exclusivity = 1_000; // 10% premium for non-designated executors

        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        Executor competitor = new Executor(address(reactorUut), wm);

        Execution memory ex = Execution({
            minAmountOut: 100,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });

        ERC20Mock(outToken).mint(address(competitor), 100);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        competitor.execute(co, ex);

        ERC20Mock(outToken).mint(address(competitor), 10);
        vm.warp(block.timestamp + 1);
        co = cosign(co);
        competitor.execute(co, ex);

        assertEq(ERC20Mock(outToken).balanceOf(recipient), 110);
    }

    function test_e2e_referral_surplus_distribution() public {
        address ref = makeAddr("ref");
        recipient = other;

        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = inAmount;
        outAmount = 500;
        outMax = type(uint256).max;

        CosignedOrder memory co = order();
        co.order.exchange.ref = ref;
        co.order.exchange.share = 1_500; // 15%

        cosignInValue = 100;
        cosignOutValue = 700;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        ERC20Mock(outToken).mint(address(exec), 1_000);
        ERC20Mock(inToken).mint(address(exec), 200);

        Execution memory ex = Execution({
            minAmountOut: 550,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 600, address(exec))
        });

        uint256 recipientBefore = ERC20Mock(outToken).balanceOf(recipient);
        uint256 refOutBefore = ERC20Mock(outToken).balanceOf(ref);
        uint256 refInBefore = ERC20Mock(inToken).balanceOf(ref);
        uint256 swapperOutBefore = ERC20Mock(outToken).balanceOf(signer);
        uint256 swapperInBefore = ERC20Mock(inToken).balanceOf(signer);

        exec.execute(co, ex);

        assertEq(ERC20Mock(outToken).balanceOf(recipient) - recipientBefore, 700);

        uint256 refOutGain = ERC20Mock(outToken).balanceOf(ref) - refOutBefore;
        uint256 refInGain = ERC20Mock(inToken).balanceOf(ref) - refInBefore;
        assertEq(refOutGain, 135);
        assertEq(refInGain, 30);

        uint256 swapperOutGain = ERC20Mock(outToken).balanceOf(signer) - swapperOutBefore;
        uint256 swapperInGain = ERC20Mock(inToken).balanceOf(signer) - swapperInBefore;
        assertEq(swapperOutGain, 765);
        assertEq(swapperInGain, 70);
    }

    function test_e2e_executor_fee_payout() public {
        address feeRecipient = makeAddr("feeRecipient");

        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = inAmount;
        outAmount = 100;
        outMax = type(uint256).max;

        CosignedOrder memory co = order();
        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        uint256 feeAmount = 50;
        ERC20Mock(inToken).mint(address(exec), feeAmount);

        Execution memory ex = Execution({
            minAmountOut: 100,
            fee: Output({token: inToken, amount: feeAmount, recipient: feeRecipient, maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 100, address(exec))
        });

        exec.execute(co, ex);

        assertEq(ERC20Mock(inToken).balanceOf(feeRecipient), feeAmount);
    }
}
