// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {DelegatingAdapter} from "src/adapter/DelegatingAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";

contract MockDelegateTarget {
    bool public wasCalled;

    function doDelegateSwap() external {
        wasCalled = true;
    }
}

contract DelegatingAdapterTest is BaseTest {
    DelegatingAdapter public adapterUut;
    MockDelegateTarget public target;

    function setUp() public override {
        super.setUp();
        adapterUut = new DelegatingAdapter();
        target = new MockDelegateTarget();
        adapter = address(adapterUut);
    }

    function test_delegateSwap_success() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(MockDelegateTarget.doDelegateSwap.selector);
        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;

        Execution memory x = executionWithTargetData(0, address(target), data);

        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function test_swap_reverts_invalid_target() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert(IExchangeAdapter.InvalidTarget.selector);
        Execution memory x = executionWithTargetData(0, address(0), hex"");
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }
}
