// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {OrderValidationLib} from "src/reactor/lib/OrderValidationLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";
import {Constants} from "src/reactor/Constants.sol";
import {BaseTest} from "test/base/BaseTest.sol";

contract OrderValidationLibFuzzTest is BaseTest {
    function callValidate(CosignedOrder memory co) external view {
        OrderValidationLib.validate(co.order);
    }

    // Keep sequential builder updates in fuzz to avoid stack-too-deep

    function testFuzz_validate_ok(
        address swapper,
        address inToken,
        address outToken,
        address recipient,
        uint256 inAmount,
        uint256 maxAmount,
        uint256 minOut,
        uint256 maxOut,
        uint256 slippage
    ) external view {
        vm.assume(swapper != address(0));
        vm.assume(inToken != address(0));
        vm.assume(recipient != address(0));
        vm.assume(inAmount > 0);
        vm.assume(maxAmount >= inAmount);
        vm.assume(maxOut >= minOut);
        vm.assume(slippage < Constants.MAX_SLIPPAGE);

        CosignedOrder memory co;
        co.order.reactor = address(this);
        co.order.exchange.adapter = address(this);
        co.order.executor = address(this);
        co.order.swapper = swapper;
        co.order.input = Input({token: inToken, amount: inAmount, maxAmount: maxAmount});
        co.order.output = Output({token: outToken, amount: minOut, maxAmount: maxOut, recipient: recipient});
        co.order.slippage = uint32(slippage);
        this.callValidate(co);
    }
}
