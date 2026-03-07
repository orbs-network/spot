// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockCallTarget {
    bool public wasCalled;
    address public lastCaller;

    function pullFromCaller(address token, uint256 amount) external {
        wasCalled = true;
        lastCaller = msg.sender;
        ERC20Mock(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract UniversalAdapterTest is BaseTest {
    UniversalAdapter public adapterUut;
    MockCallTarget public target;

    function setUp() public override {
        super.setUp();
        adapterUut = new UniversalAdapter();
        target = new MockCallTarget();
        adapter = address(adapterUut);
    }

    function test_delegateSwap_success() public {
        ERC20Mock(address(token)).mint(address(adapterUut), 1000 ether);
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockCallTarget.pullFromCaller.selector, address(token), cosignedOrder.order.input.amount
        );
        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;

        Execution memory x = executionWithTargetData(0, address(target), data);

        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertTrue(target.wasCalled());
        assertEq(target.lastCaller(), address(adapterUut));
        assertEq(ERC20Mock(address(token)).balanceOf(address(target)), cosignedOrder.order.input.amount);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(target)), 0);
    }

    function test_delegateSwap_reverts_invalid_target() public {
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
