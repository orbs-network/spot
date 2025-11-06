// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {Executor} from "src/Executor.sol";
import {OrderReactor} from "src/OrderReactor.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {RePermit} from "src/RePermit.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20Mock6Decimals} from "test/mocks/ERC20Mock6Decimals.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {SwapAdapterMock} from "test/mocks/SwapAdapter.sol";
import {ResolutionLib} from "src/lib/ResolutionLib.sol";
import {ExclusivityOverrideLib} from "src/lib/ExclusivityOverrideLib.sol";

contract OrderReactorE2ETest is BaseTest {
    OrderReactor public reactorUut;
    Executor public exec;
    DefaultDexAdapter public adapterUut;
    MockDexRouter public router;

    function setUp() public override {
        super.setUp();
        reactorUut = new OrderReactor(repermit, signer, wm);
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

        cosignInValue = 600;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = executionWithData(
            600 ether,
            abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0, address(exec))
        );

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

        cosignInValue = 1;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = execution(1 ether, address(0), 0, address(0));

        uint256 before = recipient.balance;
        exec.execute(co, ex);
        assertEq(recipient.balance - before, 1 ether);
        assertEq(address(reactorUut).balance, 0);
    }

    function test_e2e_eth_swapper_receives_reactor_surplus() public {
        inToken = address(token);
        outToken = address(0);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 1 ether;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());
        recipient = other;
        CosignedOrder memory co = order();

        fundOrderInput(co);

        uint256 surplus = 0.2 ether;
        vm.deal(address(reactorUut), surplus);

        vm.deal(address(exec), outAmount);

        cosignInValue = 1;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = execution(outAmount, address(0), 0, address(0));

        uint256 recipientBefore = recipient.balance;
        uint256 swapperBefore = swapper.balance;
        uint256 execBefore = address(exec).balance;

        exec.execute(co, ex);

        assertEq(recipient.balance - recipientBefore, outAmount, "recipient gets resolved amount");
        assertEq(swapper.balance - swapperBefore, surplus, "swapper receives reactor surplus");
        assertEq(address(exec).balance, 0, "executor distributes surplus to swapper");
        assertEq(address(reactorUut).balance, 0, "reactor swept to zero");
        assertEq(execBefore, outAmount, "executor initially funded with resolved amount");
    }

    function test_e2e_usd_to_eth_cosigned_respects_decimals() public {
        ERC20Mock6Decimals usd = new ERC20Mock6Decimals();
        token = ERC20Mock(address(usd));
        inToken = address(usd);
        outToken = address(0);
        inAmount = 50e6; // 50 USD
        inMax = inAmount;
        outAmount = 0;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());

        CosignedOrder memory co = order();

        fundOrderInput(co);

        cosignInValue = 1; // 1 USD
        cosignOutValue = 4_000; // 1 ETH costs 4000 USD
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        assertEq(co.cosignatureData.input.decimals, usd.decimals(), "input decimals should match USD token");
        assertEq(co.cosignatureData.output.decimals, 18, "output decimals should match native token");

        uint256 expectedOut = 12_500_000_000_000_000; // 0.0125 ether
        uint256 resolvedPreview = ResolutionLib.resolve(co);
        assertEq(resolvedPreview, expectedOut, "resolved amount should respect price ratio");
        vm.deal(address(exec), expectedOut);

        Execution memory ex = execution(expectedOut, address(0), 0, address(0));

        vm.recordLogs();
        uint256 before = recipient.balance;
        exec.execute(co, ex);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 settledSig = keccak256("Settled(bytes32,address,address,address,address,uint256,uint256,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == settledSig) {
                (address inTok, address outTok, uint256 recordedIn, uint256 recordedOut, uint256 recordedMin) =
                    abi.decode(entries[i].data, (address, address, uint256, uint256, uint256));
                assertEq(inTok, inToken);
                assertEq(outTok, outToken);
                assertEq(recordedIn, inAmount);
                assertEq(recordedOut, expectedOut, "settled out amount should match expected");
                assertEq(recordedMin, expectedOut, "settled min out should match expected");
            }
        }
        uint256 received = recipient.balance - before;
        assertEq(received, expectedOut);
    }

    function test_e2e_eth_to_usd_cosigned_respects_decimals() public {
        ERC20Mock6Decimals usd = new ERC20Mock6Decimals();
        token2 = ERC20Mock(address(usd));
        inToken = address(token);
        outToken = address(usd);
        inAmount = 12_500_000_000_000_000; // 0.0125 ether
        inMax = inAmount;
        outAmount = 50e6;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());

        CosignedOrder memory co = order();

        fundOrderInput(co);

        ERC20Mock(address(usd)).mint(address(exec), outAmount);

        cosignInValue = 4_000;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        assertEq(co.cosignatureData.input.decimals, 18, "input decimals should match native token");
        assertEq(co.cosignatureData.output.decimals, usd.decimals(), "output decimals should match USD token");

        uint256 expectedOut = outAmount;
        uint256 resolvedPreview = ResolutionLib.resolve(co);
        assertEq(resolvedPreview, expectedOut, "resolved amount should respect price ratio");

        Execution memory ex = execution(expectedOut, address(0), 0, address(0));

        exec.execute(co, ex);
        assertEq(ERC20Mock(address(usd)).balanceOf(recipient), outAmount);
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

        cosignInValue = 600;
        cosignOutValue = 1_000;
        co = cosign(co);
        bytes32 orderHash = OrderLib.hash(co.order);
        bytes32 permitDigest = permitDigestFor(co, address(reactorUut));
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        Execution memory ex = executionWithData(
            500 ether,
            abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 500 ether, address(exec))
        );

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

        cosignInValue = 7;
        cosignOutValue = 10;
        co = cosign(co);

        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = executionWithData(
            0.5 ether,
            abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0.5 ether, address(exec))
        );

        vm.expectRevert(ResolutionLib.CosignedExceedsStop.selector);
        exec.execute(co, ex);

        cosignInValue = 5;
        vm.warp(block.timestamp + 1);
        co = cosign(co);

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);
        assertEq(ERC20Mock(outToken).balanceOf(recipient) - before, 0.5 ether);
    }

    function test_e2e_stop_zero_allows_execution() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = 0; // stop=0 should be treated as type(uint256).max

        CosignedOrder memory co = order();

        fundOrderInput(co);

        ERC20Mock(address(token2)).mint(address(exec), 600 ether);

        cosignInValue = 1000;
        cosignOutValue = 600;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        Execution memory ex = executionWithData(
            600 ether,
            abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0, address(exec))
        );

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);

        // Should successfully execute with stop=0 even though cosigned output is high
        assertEq(ERC20Mock(outToken).balanceOf(recipient), before + 600 ether);
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

        Execution memory ex = execution(100, address(0), 0, address(0));

        ERC20Mock(outToken).mint(address(competitor), 100);
        vm.expectRevert();
        competitor.execute(co, ex);

        ERC20Mock(outToken).mint(address(competitor), 10);
        vm.warp(block.timestamp + 1);
        co = cosign(co);
        competitor.execute(co, ex);

        assertEq(ERC20Mock(outToken).balanceOf(recipient), 110);
    }

    function test_e2e_exclusivity_zero_rejects_competitor_executor() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = inAmount;
        outAmount = 100;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());

        CosignedOrder memory co = order();
        co.order.exclusivity = 0;

        cosignInValue = 1;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        Executor competitor = new Executor(address(reactorUut), wm);
        allow(address(competitor));

        Execution memory ex = execution(100, address(0), 0, address(0));

        vm.expectRevert(ExclusivityOverrideLib.InvalidSender.selector);
        competitor.execute(co, ex);
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

        cosignInValue = 7;
        cosignOutValue = 1;
        co = cosign(co);
        co.signature = permitFor(co, address(reactorUut));

        fundOrderInput(co);

        ERC20Mock(outToken).mint(address(exec), 1_000);
        ERC20Mock(inToken).mint(address(exec), 200);

        Execution memory ex = executionWithData(
            550, abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 600, address(exec))
        );

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

        Execution memory ex = executionWithFee(
            100,
            inToken,
            feeAmount,
            feeRecipient,
            abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 100, address(exec))
        );

        exec.execute(co, ex);

        assertEq(ERC20Mock(inToken).balanceOf(feeRecipient), feeAmount);
    }
}
