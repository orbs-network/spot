// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {
    CosignedOrder,
    Order,
    OrderInfo,
    Input,
    Output,
    Exchange,
    Cosignature,
    CosignedValue
} from "src/reactor/lib/OrderStructs.sol";
import {Constants} from "src/reactor/Constants.sol";

contract OrderValidationLibTest is Test {
    function callValidate(Order memory order) external view {
        CosignedOrder memory co = CosignedOrder({
            order: order,
            signature: "",
            cosignatureData: Cosignature({
                timestamp: 0,
                reactor: address(0),
                input: CosignedValue({token: address(0), value: 0, decimals: 18}),
                output: CosignedValue({token: address(0), value: 0, decimals: 18})
            }),
            cosignature: ""
        });
        OrderValidationLib.validate(co);
    }

    function _baseOrder() internal returns (Order memory o) {
        o.info.swapper = makeAddr("swapper");
        o.input.token = makeAddr("token");
        o.input.amount = 100;
        o.input.maxAmount = 200;
        o.output.token = makeAddr("tokenOut");
        o.output.amount = 50;
        o.output.maxAmount = 100;
        o.output.recipient = makeAddr("recipient");
        o.slippage = 100; // 1%
        o.executor = address(this);
    }

    function test_validate_ok() public {
        Order memory o = _baseOrder();
        this.callValidate(o);
    }

    function test_validate_reverts_inputAmountZero() public {
        Order memory o = _baseOrder();
        o.input.amount = 0;
        vm.expectRevert(OrderValidationLib.InvalidOrderInputAmountZero.selector);
        this.callValidate(o);
    }

    function test_validate_reverts_inputAmountGtMax() public {
        Order memory o = _baseOrder();
        o.input.amount = o.input.maxAmount + 1;
        vm.expectRevert(OrderValidationLib.InvalidOrderInputAmountGtMax.selector);
        this.callValidate(o);
    }

    function test_validate_reverts_outputAmountGtMax() public {
        Order memory o = _baseOrder();
        o.output.amount = o.output.maxAmount + 1;
        vm.expectRevert(OrderValidationLib.InvalidOrderOutputAmountGtMax.selector);
        this.callValidate(o);
    }

    function test_validate_reverts_slippageTooHigh() public {
        Order memory o = _baseOrder();
        o.slippage = uint32(Constants.MAX_SLIPPAGE); // >= MAX_SLIPPAGE
        vm.expectRevert(OrderValidationLib.InvalidOrderSlippageTooHigh.selector);
        this.callValidate(o);
    }

    function test_validate_reverts_inputTokenZero() public {
        Order memory o = _baseOrder();
        o.input.token = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderInputTokenZero.selector);
        this.callValidate(o);
    }

    function test_validate_reverts_outputRecipientZero() public {
        Order memory o = _baseOrder();
        o.output.recipient = address(0);
        vm.expectRevert(OrderValidationLib.InvalidOrderOutputRecipientZero.selector);
        this.callValidate(o);
    }

    function test_validate_allows_override_when_exclusivity_set() public {
        Order memory o = _baseOrder();
        o.exclusivity = 100; // 1%
        address notExecutor = makeAddr("notExecutor");
        vm.prank(notExecutor);
        this.callValidate(o);
    }
}
