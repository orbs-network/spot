// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OrderValidationLib} from "src/lib/OrderValidationLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";
import {Constants} from "src/Constants.sol";
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
        vm.assume(outToken != address(0));
        vm.assume(recipient != address(0));
        vm.assume(inToken != outToken);
        vm.assume(inAmount > 0);
        vm.assume(maxAmount >= inAmount);
        vm.assume(maxOut >= minOut);
        vm.assume(slippage <= Constants.MAX_SLIPPAGE);

        CosignedOrder memory co;
        co.order.reactor = address(this);
        co.order.exchange.adapter = address(this);
        co.order.executor = address(this);
        co.order.swapper = swapper;
        co.order.input = Input({token: inToken, amount: inAmount, maxAmount: maxAmount});
        co.order.output = Output({token: outToken, limit: minOut, stop: maxOut, recipient: recipient});
        co.order.slippage = uint32(slippage);
        co.order.deadline = block.timestamp + 1;
        co.order.chainid = block.chainid;
        this.callValidate(co);
    }
}
