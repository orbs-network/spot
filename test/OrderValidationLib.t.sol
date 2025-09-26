// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BaseTest} from "test/base/BaseTest.sol";

import {OrderValidationLib} from "src/lib/OrderValidationLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";
import {Constants} from "src/reactor/Constants.sol";

contract OrderValidationLibTest is BaseTest {
    function callValidate(CosignedOrder memory co) external view {
        OrderValidationLib.validate(co.order);
    }

    function test_validate_ok() public {
        // Ensure non-zero reactor/executor/adapter + sane amounts
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        this.callValidate(order());
    }

    function test_validate_reverts_inputAmountZero() public {
        inAmount = 0;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderInputAmountZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_inputAmountGtMax() public {
        inAmount = 201;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderInputAmountGtMax.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_outputAmountGtMax() public {
        inAmount = 100;
        inMax = 200;
        outAmount = 101;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderOutputAmountGtMax.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_slippageTooHigh() public {
        slippage = uint32(Constants.MAX_SLIPPAGE);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderSlippageTooHigh.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_inputTokenZero() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(0);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderInputTokenZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_outputRecipientZero() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        inAmount = 100;
        inMax = 200;
        outToken = address(token2);
        outAmount = 50;
        outMax = 100;
        recipient = address(0);
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderOutputRecipientZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_exchangeShareTooHigh() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.exchange.share = uint32(Constants.BPS + 1);
        vm.expectRevert(OrderValidationLib.InvalidOrderExchangeShareBps.selector);
        this.callValidate(co);
    }

    function test_validate_allows_override_when_exclusivity_set() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.exclusivity = 100;
        address notExecutor = makeAddr("notExecutor");
        vm.prank(notExecutor);
        this.callValidate(co);
    }

    function test_validate_reverts_reactor_zero() public {
        executor = address(this);
        adapter = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.reactor = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderReactorZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_executor_zero() public {
        reactor = address(this);
        adapter = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.executor = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderExecutorZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_adapter_zero() public {
        reactor = address(this);
        executor = address(this);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.exchange.adapter = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderAdapterZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_swapper_zero() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.swapper = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderSwapperZero.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_deadline_expired() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.deadline = block.timestamp - 1;
        vm.expectRevert(OrderValidationLib.InvalidOrderDeadlineExpired.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_deadline_zero() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.deadline = 0;
        vm.expectRevert(OrderValidationLib.InvalidOrderDeadlineExpired.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_chainid_mismatch() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        co.order.chainid = block.chainid + 1;
        vm.expectRevert(OrderValidationLib.InvalidOrderChainid.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_reactor_mismatch() public {
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        reactor = makeAddr("reactorMismatch");
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderReactorMismatch.selector);
        this.callValidate(co);
    }

    function test_validate_reverts_same_input_output_token() public {
        reactor = address(this);
        executor = address(this);
        adapter = address(this);
        inToken = address(token);
        outToken = address(token); // Same token as input
        inAmount = 100;
        inMax = 200;
        outAmount = 50;
        outMax = 100;
        CosignedOrder memory co = order();
        vm.expectRevert(OrderValidationLib.InvalidOrderSameToken.selector);
        this.callValidate(co);
    }
}
