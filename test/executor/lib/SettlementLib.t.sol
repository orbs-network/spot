// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";

import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/types/OrderTypes.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract SettlementWrapper {
    function settle(CosignedOrder memory cosignedOrder, SettlementLib.Execution memory execution, address, address)
        external
    {
        SettlementLib.settle(OrderLib.hash(cosignedOrder.order), cosignedOrder, execution);
    }
}

contract SettlementLibTest is BaseTest {
    USDTMock public usdt;
    address public testReactor = makeAddr("reactor");
    address public testSwapper = makeAddr("swapper");
    address public feeRecipient = makeAddr("feeRecipient");
    address public exchange = makeAddr("exchange");

    SettlementWrapper public wrapper;

    // Duplicate event signature for expectEmit matching
    event Settled(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed exchange,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    );

    function setUp() public override {
        super.setUp();
        usdt = new USDTMock();
        wrapper = new SettlementWrapper();
        // reactor/adapter specified per order via helper
        exchange = makeAddr("exchange");
    }

    // No per-test builders; set BaseTest vars and use order() in tests

    // (helpers removed; inline in tests)

    // No expect helpers; inline event expectations in tests that need them

    function test_settle_basic_functionality() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 minAmountOut = 95 ether;

        // Suite defaults
        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper; // executor default 0
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(minAmountOut, address(0), 0, address(0));

        ERC20Mock(address(token2)).mint(address(wrapper), outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        vm.expectEmit(address(wrapper));
        emit Settled(
            OrderLib.hash(order.order),
            swapper,
            exchange,
            order.order.input.token,
            order.order.output.token,
            inAmount,
            outAmount
        );
        wrapper.settle(order, execution, reactor, exchange);
    }

    function test_settle_with_min_amount_out_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 95 ether;
        uint256 minAmountOut = 100 ether;
        uint256 shortfall = minAmountOut - outAmount;

        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper;
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(minAmountOut, address(0), 0, address(0));

        ERC20Mock(address(token2)).mint(address(wrapper), shortfall + outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        uint256 initialBalance = ERC20Mock(address(token2)).balanceOf(recipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(ERC20Mock(address(token2)).balanceOf(recipient), initialBalance + shortfall);
    }

    function test_settle_with_gas_fee_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 feeAmount = 5 ether;

        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper;
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(95 ether, address(token2), feeAmount, feeRecipient);

        ERC20Mock(address(token2)).mint(address(wrapper), feeAmount + outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        uint256 initialBalance = ERC20Mock(address(token2)).balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(ERC20Mock(address(token2)).balanceOf(feeRecipient), initialBalance + feeAmount);
    }

    function test_settle_with_eth_gas_fee() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 feeAmount = 1 ether;

        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper;
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(95 ether, address(0), feeAmount, feeRecipient);

        vm.deal(address(wrapper), feeAmount);
        ERC20Mock(address(token2)).mint(address(wrapper), outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        uint256 initialBalance = feeRecipient.balance;
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(feeRecipient.balance, initialBalance + feeAmount);
    }

    function test_settle_with_zero_gas_fee_skips_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;

        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper;
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(95 ether, address(token2), 0, feeRecipient);

        ERC20Mock(address(token2)).mint(address(wrapper), outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        uint256 initialBalance = ERC20Mock(address(token2)).balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(ERC20Mock(address(token2)).balanceOf(feeRecipient), initialBalance);
    }

    function test_settle_handles_usdt_like_tokens() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100e6;
        uint256 feeAmount = 5e6;

        reactor = testReactor;
        adapter = exchange;
        swapper = testSwapper;
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(95e6, address(usdt), feeAmount, feeRecipient);

        usdt.mint(address(wrapper), feeAmount + outAmount);
        usdt.mint(reactor, outAmount);

        uint256 initialBalance = usdt.balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(usdt.balanceOf(feeRecipient), initialBalance + feeAmount);
    }

    function test_settle_with_both_shortfall_and_fee() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 95 ether;
        uint256 minAmountOut = 100 ether;
        uint256 shortfall = minAmountOut - outAmount;
        uint256 feeAmount = 10 ether;

        reactor = testReactor;
        adapter = exchange;
        executor = address(0);
        swapper = testSwapper;
        inToken = address(token);
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        outToken = address(token2);
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(minAmountOut, address(token2), feeAmount, feeRecipient);

        ERC20Mock(address(token2)).mint(address(wrapper), shortfall + feeAmount + outAmount);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        uint256 initialRecipientBalance = ERC20Mock(address(token2)).balanceOf(recipient);
        uint256 initialFeeBalance = ERC20Mock(address(token2)).balanceOf(feeRecipient);

        wrapper.settle(order, execution, reactor, exchange);

        assertEq(ERC20Mock(address(token2)).balanceOf(recipient), initialRecipientBalance + shortfall);
        assertEq(ERC20Mock(address(token2)).balanceOf(feeRecipient), initialFeeBalance + feeAmount);
    }

    function testFuzz_settle_result_values(uint128 inAmount, uint128 outAmount, uint128 minAmountOut, uint128 feeAmount)
        public
    {
        vm.assume(inAmount > 0 && outAmount > 0);

        reactor = testReactor;
        adapter = exchange;
        executor = address(0);
        swapper = testSwapper;
        inToken = address(token);
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        outToken = address(token2);
        BaseTest.outAmount = outAmount;
        BaseTest.outMax = type(uint256).max;
        recipient = swapper;
        CosignedOrder memory order = order();

        SettlementLib.Execution memory execution = execution(minAmountOut, address(token2), feeAmount, feeRecipient);

        uint256 neededTokens =
            uint256(feeAmount) + outAmount + (minAmountOut > outAmount ? minAmountOut - outAmount : 0);
        ERC20Mock(address(token2)).mint(address(wrapper), neededTokens);
        ERC20Mock(address(token2)).mint(reactor, outAmount);

        vm.expectEmit(address(wrapper));
        emit Settled(
            OrderLib.hash(order.order),
            swapper,
            exchange,
            order.order.input.token,
            order.order.output.token,
            inAmount,
            outAmount
        );
        wrapper.settle(order, execution, reactor, exchange);
    }

    // Helper function to receive ETH
    receive() external payable {}
}
