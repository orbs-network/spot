// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";

import {Executor} from "src/Executor.sol";
import {WMAllowed} from "src/lib/WMAllowed.sol";
import {Execution} from "src/Structs.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {OrderLib} from "src/lib/OrderLib.sol";
import {SettlementLib} from "src/lib/SettlementLib.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";
import {SwapAdapterMock} from "test/mocks/SwapAdapter.sol";

contract ExecutorTest is BaseTest {
    Executor public exec;
    MockReactor public reactorMock;
    SwapAdapterMock public adapterMock;
    address public ref;
    uint16 public refShare = 1000; // 10% in bps

    function setUp() public override {
        super.setUp();
        vm.warp(1 days);

        reactorMock = new MockReactor();
        exec = new Executor(address(reactorMock), wm);
        adapterMock = new SwapAdapterMock();

        ref = makeAddr("ref");

        // set base vars once for this suite
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        // allow this test as caller
        allowThis();
    }

    function _mint(address tkn, address to, uint256 amt) internal {
        ERC20Mock(tkn).mint(to, amt);
    }

    function test_execute_forwards_to_reactor_with_callback() public {
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outMax = 0;
        CosignedOrder memory co = order();
        _mint(co.order.output.token, address(exec), co.order.output.limit);
        Execution memory ex = execution(0, address(0), 0, address(0));
        exec.execute(co, ex);

        assertEq(reactorMock.lastSender(), address(exec));

        // Get the components of the lastOrder struct
        (Order memory order, bytes memory signature, Cosignature memory cosignatureData, bytes memory cosignature) =
            reactorMock.lastOrder();
        CosignedOrder memory lastOrder = CosignedOrder({
            order: order, signature: signature, cosignatureData: cosignatureData, cosignature: cosignature
        });

        // Compare the order structures (we can't compare the signature as it might be different)
        assertTrue(keccak256(abi.encode(lastOrder.order)) == keccak256(abi.encode(co.order)));

        // Check that the exchange and execution parameters were passed correctly
        assertEq(reactorMock.lastExchange(), address(adapterMock));

        // Compare the execution parameters
        Execution memory actualExecution = reactorMock.lastExecution();
        Execution memory expectedExecution = execution(0, address(0), 0, address(0));
        assertEq(keccak256(abi.encode(actualExecution)), keccak256(abi.encode(expectedExecution)));
    }

    function test_execute_reverts_when_not_allowed() public {
        disallowThis();

        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outMax = 0;
        CosignedOrder memory co = order();
        Execution memory ex = execution(0, address(0), 0, address(0));
        vm.expectRevert(abi.encodeWithSelector(WMAllowed.NotAllowed.selector));
        exec.execute(co, ex);
    }

    function test_reactorCallback_onlyReactor() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 0;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));
    }

    function test_reactorCallback_executes_multicall_and_sets_erc20_approval() public {
        // mint to executor
        _mint(address(token), address(exec), 1e18);

        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 1234;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        // call from reactor
        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));

        // multicall executed: executor now holds minted tokens
        assertEq(ERC20Mock(address(token)).balanceOf(address(exec)), 1e18);

        // approval set for reactor to allowance + amount
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactorMock)), 1234);
    }

    function test_reactorCallback_handles_usdt_like_tokens_forceApprove_exact() public {
        // deploy USDT-like token that reverts on non-zero->non-zero approvals
        USDTMock usdt = new USDTMock();

        // pre-set a non-zero allowance from executor to reactor
        hoax(address(exec));
        usdt.approve(address(reactorMock), 1);

        // mint to executor
        _mint(address(usdt), address(exec), 1e18);

        // resolved order outputs USDT to reactor via approval path
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(usdt);
        outAmount = 1234;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        // call from reactor; should internally forceApprove to exact amount (approve(0) then approve(1234))
        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));

        // final allowance set to exact amount
        assertEq(IERC20(address(usdt)).allowance(address(exec), address(reactorMock)), 1234);
    }

    function test_reactorCallback_handles_eth_output_and_sends_to_reactor() public {
        // fund executor to cover sendValue
        vm.deal(address(exec), 1 ether);

        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(0);
        outAmount = 987;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        uint256 beforeBal = address(reactorMock).balance;
        vm.prank(address(reactorMock), address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));
        assertEq(address(reactorMock).balance, beforeBal + 987);
    }

    function test_reactorCallback_allows_single_output_to_non_swapper() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 100;
        outMax = type(uint256).max;
        recipient = other;
        CosignedOrder memory co = order();
        _mint(co.order.output.token, address(exec), co.order.output.limit);
        bytes32 orderHash = OrderLib.hash(co.order);

        // should not revert; also sets approval for reactor
        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactorMock)), 100);
    }

    function test_reactorCallback_reverts_when_insufficient_post_swap_amount() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 100;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        startHoax(address(reactorMock));
        vm.expectRevert(
            abi.encodeWithSelector(
                SettlementLib.InsufficientPostSwapBalance.selector, 0, co.order.output.limit, 0, co.order.output.limit
            )
        );
        exec.reactorCallback(orderHash, co.order.output.limit, co, execution(0, address(0), 0, address(0)));
        vm.stopPrank();
    }

    function test_reactorCallback_reverts_when_insufficient_post_swap_amount_multiple_outputs() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 100;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        Output[] memory fees = new Output[](2);
        fees[0] = Output({token: co.order.output.token, limit: 40, stop: type(uint256).max, recipient: signer});
        fees[1] = Output({token: co.order.output.token, limit: 60, stop: type(uint256).max, recipient: other});
        Execution memory params = executionWithFees(0, fees);

        startHoax(address(reactorMock));
        vm.expectRevert(
            abi.encodeWithSelector(
                SettlementLib.InsufficientPostSwapBalance.selector, 0, co.order.output.limit, 100, 200
            )
        );
        exec.reactorCallback(orderHash, co.order.output.limit, co, params);
        vm.stopPrank();
    }

    function test_reactorCallback_allows_multiple_same_token_outputs_when_funded() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 100;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        Output[] memory fees = new Output[](2);
        fees[0] = Output({token: co.order.output.token, limit: 40, stop: type(uint256).max, recipient: signer});
        fees[1] = Output({token: co.order.output.token, limit: 60, stop: type(uint256).max, recipient: other});
        Execution memory params = executionWithFees(0, fees);

        uint256 funded = co.order.output.limit + fees[0].limit + fees[1].limit;
        _mint(co.order.output.token, address(exec), funded);

        uint256 signerBefore = ERC20Mock(address(token)).balanceOf(signer);
        uint256 otherBefore = ERC20Mock(address(token)).balanceOf(other);

        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, params);

        assertEq(IERC20(address(token)).allowance(address(exec), address(reactorMock)), co.order.output.limit);
        assertEq(ERC20Mock(address(token)).balanceOf(signer), signerBefore + fees[0].limit);
        assertEq(ERC20Mock(address(token)).balanceOf(other), otherBefore + fees[1].limit);
        assertEq(
            ERC20Mock(address(token)).balanceOf(address(exec)),
            co.order.output.limit,
            "executor retains resolved amount until reactor pulls"
        );
    }

    function test_reactorCallback_ignores_non_matching_fee_tokens_in_guard() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outAmount = 80;
        outMax = type(uint256).max;
        recipient = signer;
        CosignedOrder memory co = order();
        bytes32 orderHash = OrderLib.hash(co.order);

        Output[] memory fees = new Output[](2);
        fees[0] = Output({token: co.order.output.token, limit: 30, stop: type(uint256).max, recipient: signer});
        fees[1] = Output({token: address(token2), limit: 70, stop: type(uint256).max, recipient: other});
        Execution memory params = executionWithFees(0, fees);

        _mint(co.order.output.token, address(exec), co.order.output.limit + fees[0].limit);
        _mint(address(token2), address(exec), fees[1].limit);

        uint256 signerBefore = ERC20Mock(address(token)).balanceOf(signer);
        uint256 otherBeforeOrder = ERC20Mock(address(token)).balanceOf(other);
        uint256 otherBeforeToken2 = ERC20Mock(address(token2)).balanceOf(other);

        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, params);

        assertEq(IERC20(address(token)).allowance(address(exec), address(reactorMock)), co.order.output.limit);
        assertEq(ERC20Mock(address(token)).balanceOf(address(exec)), co.order.output.limit);
        assertEq(ERC20Mock(address(token)).balanceOf(signer), signerBefore + fees[0].limit);
        assertEq(ERC20Mock(address(token)).balanceOf(other), otherBeforeOrder);
        assertEq(ERC20Mock(address(token2)).balanceOf(other), otherBeforeToken2 + fees[1].limit);
    }

    // NOTE: This test is no longer relevant as the new protocol only supports single output per order
    // function test_reactorCallback_reverts_on_mixed_out_tokens_to_swapper() public {
    //     ERC20Mock token2 = new ERC20Mock();
    //     OutputToken[] memory outs = new OutputToken[](2);
    //     outs[0] = Output({token: address(token), amount: 100, recipient: signer, maxAmount: type(uint256).max});
    //     outs[1] = Output({token: address(token2), amount: 1, recipient: signer, maxAmount: type(uint256).max});
    //
    //     CosignedOrder[] memory ros = new CosignedOrder[](1);
    //     ros[0] = _dummyCosignedOrder(address(token), 0);
    //     ros[0].outputs = outs;
    //
    //     hoax(address(reactorMock));
    //     vm.expectRevert(Executor.InvalidOrder.selector);
    //     exec.reactorCallback(
    //         ros,
    //         abi.encode(
    //             address(adapter),
    //             Execution({
    //                 fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
    //                 minAmountOut: 0,
    //                 data: hex""
    //             })
    //         )
    //     );
    // }

    function test_reactorCallback_transfers_delta_to_swapper_when_outAmountSwapper_greater() public {
        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token2);
        outAmount = 500;
        outMax = type(uint256).max;
        CosignedOrder memory co = order();
        Execution memory execParams = execution(600, address(0), 0, address(0));
        _mint(co.order.output.token, address(exec), execParams.minAmountOut);
        bytes32 orderHash = OrderLib.hash(co.order);

        uint256 before = ERC20Mock(address(token2)).balanceOf(signer);
        hoax(address(reactorMock));
        exec.reactorCallback(orderHash, co.order.output.limit, co, execParams);
        assertEq(ERC20Mock(address(token2)).balanceOf(signer), before + 100);
    }

    function test_e2e_execute_callback_and_surplus() public {
        reactor = address(reactorMock);
        adapter = address(adapter);
        executor = address(exec);
        outAmount = 500;
        outMax = 500;
        CosignedOrder memory co = order();
        co.order.exchange.ref = ref;
        co.order.exchange.share = refShare;

        // use CosignedOrder directly in execute

        _mint(address(token2), address(exec), 1000);
        _mint(address(token), address(exec), 200);

        Execution memory ex2 = execution(600, address(0), 0, address(0));
        exec.execute(co, ex2);

        assertEq(IERC20(address(token2)).allowance(address(exec), address(reactorMock)), 500);
        assertEq(ERC20Mock(address(token2)).balanceOf(ref), 90);
        assertEq(ERC20Mock(address(token2)).balanceOf(signer), 910);
        assertEq(token.balanceOf(ref), 20);
        assertEq(token.balanceOf(signer), 180);
        assertEq(ERC20Mock(address(token2)).balanceOf(address(exec)), 0);
        assertEq(token.balanceOf(address(exec)), 0);
    }

    // No per-test builders; set BaseTest vars inline in tests

    function test_execution_with_gas_fee_fields() public {
        // Test that the new gas fee fields can be set and used
        address feeToken = address(token); // Use actual token for gas fee
        uint256 feeAmount = 1000;
        address feeRecipient = makeAddr("gasFeeRecipient");

        reactor = address(reactorMock);
        adapter = address(adapterMock);
        executor = address(exec);
        inAmount = 0;
        inMax = 0;
        outToken = address(token);
        outMax = 0;
        CosignedOrder memory co = order();
        _mint(feeToken, address(exec), feeAmount + co.order.output.limit);

        Execution memory ex = execution(0, feeToken, feeAmount, feeRecipient);

        uint256 balanceBefore = IERC20(feeToken).balanceOf(feeRecipient);
        exec.execute(co, ex);

        // Verify that gas fee was transferred to the recipient
        uint256 balanceAfter = IERC20(feeToken).balanceOf(feeRecipient);
        assertEq(balanceAfter, balanceBefore + feeAmount);
    }
}
