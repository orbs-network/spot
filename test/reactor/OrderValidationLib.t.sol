// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";

import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/types/OrderTypes.sol";
import {Constants} from "src/reactor/Constants.sol";

contract OrderValidationLibTest is BaseTest {
    function callValidate(CosignedOrder memory co) external pure {
        OrderValidationLib.validate(co.order);
    }

    function test_validate_ok() public {
        // Use BaseTest tokens and defaults; override only amounts
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

    function test_validate_allows_override_when_exclusivity_set() public {
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
}
