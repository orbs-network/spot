// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {DynamicP2DexAdapter} from "src/adapter/DynamicP2DexAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";
import {Executor} from "src/Executor.sol";

contract Permit2Target is MockDexRouter {
    function pull(MockPermit2 permit2, address token, address from, uint160 amount) external {
        permit2.transferFrom(from, address(this), amount, token);
    }

    function swapThroughPreviousTarget(
        Permit2Target previousTarget,
        MockPermit2 permit2,
        address tokenIn,
        uint160 amount,
        uint160 stolenAmount,
        ERC20Mock tokenOut
    ) external {
        previousTarget.pull(permit2, tokenIn, msg.sender, stolenAmount);
        ERC20Mock(tokenIn).transferFrom(msg.sender, address(this), amount);
        tokenOut.mint(msg.sender, amount);
    }
}

contract DynamicP2DexAdapterTest is BaseTest {
    DynamicP2DexAdapter public adapterUut;
    MockDexRouter public routerA;
    MockDexRouter public routerB;
    MockPermit2 public permit2;

    function setUp() public override {
        super.setUp();
        routerA = new MockDexRouter();
        routerB = new MockDexRouter();
        permit2 = new MockPermit2();
        adapterUut = new DynamicP2DexAdapter(address(permit2));

        ERC20Mock(address(token)).mint(address(adapterUut), 2000 ether);
        adapter = address(adapterUut);
    }

    function test_swap_uses_dynamic_target_for_permit2_and_call() public {
        _swapThrough(address(routerA), 1000 ether);
        assertEq(ERC20Mock(address(token)).balanceOf(address(routerA)), 1000 ether);
        _assertPermit2Approval(address(routerA));

        _swapThrough(address(routerB), 500 ether);
        assertEq(ERC20Mock(address(token)).balanceOf(address(routerB)), 500 ether);
        _assertPermit2Approval(address(routerB));
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

    function test_previous_target_can_steal_executor_surplus_during_later_swap() public {
        Executor exec = new Executor(address(this), wm);
        Permit2Target previousTarget = new Permit2Target();
        Permit2Target currentTarget = new Permit2Target();
        executor = address(exec);
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = inAmount;

        token.mint(executor, inAmount);
        _swapThroughExecutor(
            exec,
            address(previousTarget),
            abi.encodeCall(MockDexRouter.doSwap, (address(token), inAmount, address(token2), inAmount, executor))
        );
        token2.transferFrom(executor, signer, outAmount);

        (,, uint160 remaining, uint48 expiration) = permit2.allowance(executor, address(token), address(previousTarget));
        assertEq(remaining, type(uint160).max);
        assertEq(expiration, type(uint48).max);
        assertEq(token.allowance(executor, address(previousTarget)), 0);
        assertEq(token.allowance(executor, address(permit2)), 0);

        // The executor holds surplus plus the next order's input, but ERC20 cleanup blocks an idle pull.
        uint256 surplus = 500 ether;
        vm.warp(block.timestamp + 1 days);
        token.mint(executor, surplus + inAmount);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(permit2), 0, inAmount
            )
        );
        previousTarget.pull(permit2, address(token), executor, uint160(inAmount));

        // A different target calls the old target while the later swap reopens the ERC20 allowance.
        _swapThroughExecutor(
            exec,
            address(currentTarget),
            abi.encodeCall(
                Permit2Target.swapThroughPreviousTarget,
                (previousTarget, permit2, address(token), uint160(inAmount), uint160(surplus), token2)
            )
        );

        assertEq(token.balanceOf(address(previousTarget)), inAmount + surplus);
        assertEq(token.balanceOf(address(currentTarget)), inAmount);
        assertEq(token.balanceOf(executor), 0);
        assertEq(token2.balanceOf(executor), outAmount);
        assertEq(token.allowance(executor, address(currentTarget)), 0);
        assertEq(token.allowance(executor, address(permit2)), 0);
    }

    function _swapThroughExecutor(Executor exec, address target, bytes memory data) internal {
        CosignedOrder memory co = order();
        exec.reactorCallback(
            OrderLib.hash(co.order), co.order.output.limit, co, executionWithTargetData(0, target, data)
        );
    }

    function _swapThrough(address target, uint256 amount) internal {
        inAmount = amount;
        inMax = amount;
        outAmount = amount / 2;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), amount, address(token2), amount, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithTargetData(0, target, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), target), 0);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(permit2)), 0);
    }

    function _assertPermit2Approval(address target) internal view {
        (address approvedToken, address approvedSpender, uint160 amount, uint48 expiration) = permit2.lastApproval();
        assertEq(approvedToken, address(token));
        assertEq(approvedSpender, target);
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
    }
}
