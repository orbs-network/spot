// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";

import {ResolutionLib} from "src/lib/ResolutionLib.sol";
import {CosignedOrder, CosignedValue} from "src/Structs.sol";
import {Constants} from "src/Constants.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ResolutionLibFuzzTest is BaseTest {
    function callResolve(CosignedOrder memory co) external pure returns (uint256) {
        return ResolutionLib.resolve(co);
    }

    function testFuzz_resolveOutAmount_bounds(
        uint256 inAmount,
        uint256 limit,
        uint256 lowerTrigger,
        uint256 upperTrigger,
        uint256 inputValue,
        uint256 outputValue,
        uint256 slippage
    ) external {
        vm.assume(inAmount > 0 && inAmount < type(uint128).max);
        vm.assume(limit < type(uint128).max);
        vm.assume(upperTrigger < type(uint128).max);
        vm.assume(lowerTrigger <= upperTrigger);
        vm.assume(inputValue > 0 && outputValue > 0 && inputValue < 1e36 && outputValue < 1e36);
        vm.assume(slippage <= Constants.MAX_SLIPPAGE);

        BaseTest.slippage = uint32(slippage);
        // default freshness is 1
        BaseTest.executor = address(this);
        BaseTest.inToken = address(token);
        BaseTest.inAmount = inAmount;
        BaseTest.inMax = inAmount;
        BaseTest.outToken = address(token2);
        BaseTest.outAmount = limit;
        BaseTest.triggerLower = lowerTrigger;
        BaseTest.triggerUpper = upperTrigger;
        CosignedOrder memory co = order();
        co.trigger.input = CosignedValue({token: BaseTest.inToken, value: inputValue, decimals: 18});
        co.trigger.output = CosignedValue({token: BaseTest.outToken, value: outputValue, decimals: 18});
        co.current.input = CosignedValue({token: BaseTest.inToken, value: inputValue, decimals: 18});
        co.current.output = CosignedValue({token: BaseTest.outToken, value: outputValue, decimals: 18});

        uint256 cosignedOutput = Math.mulDiv(inAmount, inputValue, outputValue);
        bool lowerSet = lowerTrigger != 0;
        bool upperSet = upperTrigger != 0;
        bool triggerMet;
        if (lowerSet && upperSet) {
            triggerMet = cosignedOutput <= lowerTrigger || cosignedOutput >= upperTrigger;
        } else if (lowerSet) {
            triggerMet = cosignedOutput <= lowerTrigger;
        } else if (upperSet) {
            triggerMet = cosignedOutput >= upperTrigger;
        } else {
            triggerMet = true;
        }

        if (!triggerMet) {
            vm.expectRevert(ResolutionLib.NotTriggered.selector);
            this.callResolve(co);
            return;
        }

        uint256 minOut = Math.mulDiv(cosignedOutput, Constants.BPS - slippage, Constants.BPS);
        uint256 expected = minOut > limit ? minOut : limit;
        uint256 outAmt = this.callResolve(co);
        assertEq(outAmt, expected);
    }
}
