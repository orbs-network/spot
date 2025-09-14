// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";

import {Executor} from "src/executor/Executor.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {IValidationCallback} from "src/interface/IValidationCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";
import {SwapAdapterMock} from "test/mocks/SwapAdapter.sol";

contract ExecutorTest is BaseTest {
    Executor public exec;
    MockReactor public reactor;
    SwapAdapterMock public adapter;
    ERC20Mock public tokenOut;
    address public ref;
    uint16 public refShare = 1000; // 10% in bps

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);

        reactor = new MockReactor();
        exec = new Executor(address(reactor), wm);
        adapter = new SwapAdapterMock();

        tokenOut = new ERC20Mock();
        ref = makeAddr("ref");

        // allow this test as caller
        allowThis();
    }

    function _mint(address tkn, address to, uint256 amt) internal {
        ERC20Mock(tkn).mint(to, amt);
    }

    function test_execute_forwards_to_reactor_with_callback() public {
        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({reactor: address(reactor), swapper: signer, nonce: 0, deadline: 1_086_400});
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0, data: ""});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});
        SettlementLib.Execution memory ex = SettlementLib.Execution({
            minAmountOut: 0,
            fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });
        exec.execute(co, ex);

        assertEq(reactor.lastSender(), address(exec));

        // Get the components of the lastOrder struct
        (
            OrderLib.Order memory order,
            bytes memory signature,
            OrderLib.Cosignature memory cosignatureData,
            bytes memory cosignature
        ) = reactor.lastOrder();
        OrderLib.CosignedOrder memory lastOrder = OrderLib.CosignedOrder({
            order: order,
            signature: signature,
            cosignatureData: cosignatureData,
            cosignature: cosignature
        });

        // Compare the order structures (we can't compare the signature as it might be different)
        assertTrue(keccak256(abi.encode(lastOrder.order)) == keccak256(abi.encode(co.order)));

        // Check that the exchange and execution parameters were passed correctly
        assertEq(reactor.lastExchange(), address(adapter));

        // Get the components of the lastExecution struct
        (uint256 minAmountOut, OrderLib.Output memory fee, bytes memory data) = reactor.lastExecution();
        SettlementLib.Execution memory actualExecution =
            SettlementLib.Execution({minAmountOut: minAmountOut, fee: fee, data: data});

        SettlementLib.Execution memory expectedExecution = SettlementLib.Execution({
            minAmountOut: 0,
            fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });
        assertEq(keccak256(abi.encode(actualExecution)), keccak256(abi.encode(expectedExecution)));
    }

    function test_execute_reverts_when_not_allowed() public {
        disallowThis();

        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({reactor: address(reactor), swapper: signer, nonce: 0, deadline: 1_086_400});
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0, data: ""});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});
        SettlementLib.Execution memory ex = SettlementLib.Execution({
            minAmountOut: 0,
            fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });
        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.execute(co, ex);
    }

    function test_reactorCallback_onlyReactor() public {
        OrderLib.CosignedOrder memory co = _dummyCosignedOrder(address(token), 0);
        bytes32 orderHash = OrderLib.hash(co.order);

        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 0,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );
    }

    function test_reactorCallback_executes_multicall_and_sets_erc20_approval() public {
        // mint to executor
        _mint(address(token), address(exec), 1e18);

        OrderLib.CosignedOrder memory co = _dummyCosignedOrder(address(token), 1234);
        bytes32 orderHash = OrderLib.hash(co.order);

        // call from reactor
        vm.prank(address(reactor));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 0,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );

        // multicall executed: executor now holds minted tokens
        assertEq(ERC20Mock(address(token)).balanceOf(address(exec)), 1e18);

        // approval set for reactor to allowance + amount
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactor)), 1234);
    }

    function test_reactorCallback_handles_usdt_like_tokens_forceApprove_exact() public {
        // deploy USDT-like token that reverts on non-zero->non-zero approvals
        USDTMock usdt = new USDTMock();

        // pre-set a non-zero allowance from executor to reactor
        vm.prank(address(exec));
        usdt.approve(address(reactor), 1);

        // mint to executor
        _mint(address(usdt), address(exec), 1e18);

        // resolved order outputs USDT to reactor via approval path
        OrderLib.CosignedOrder memory co = _dummyCosignedOrder(address(usdt), 1234);
        bytes32 orderHash = OrderLib.hash(co.order);

        // call from reactor; should internally forceApprove to exact amount (approve(0) then approve(1234))
        vm.prank(address(reactor));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 0,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );

        // final allowance set to exact amount
        assertEq(IERC20(address(usdt)).allowance(address(exec), address(reactor)), 1234);
    }

    function test_reactorCallback_handles_eth_output_and_sends_to_reactor() public {
        // fund executor to cover sendValue
        vm.deal(address(exec), 1 ether);

        OrderLib.CosignedOrder memory co = _dummyCosignedOrder(address(0), 987);
        bytes32 orderHash = OrderLib.hash(co.order);

        uint256 beforeBal = address(reactor).balance;
        vm.prank(address(reactor));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 0,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );
        assertEq(address(reactor).balance, beforeBal + 987);
    }

    function test_reactorCallback_allows_single_output_to_non_swapper() public {
        OrderLib.CosignedOrder memory co = _dummyCosignedOrderWithRecipient(address(token), 100, other);
        bytes32 orderHash = OrderLib.hash(co.order);

        // should not revert; also sets approval for reactor
        vm.prank(address(reactor));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 0,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactor)), 100);
    }

    // NOTE: This test is no longer relevant as the new protocol only supports single output per order
    // function test_reactorCallback_reverts_on_mixed_out_tokens_to_swapper() public {
    //     ERC20Mock token2 = new ERC20Mock();
    //     OrderLib.OutputToken[] memory outs = new OrderLib.OutputToken[](2);
    //     outs[0] = OrderLib.Output({token: address(token), amount: 100, recipient: signer, maxAmount: type(uint256).max});
    //     outs[1] = OrderLib.Output({token: address(token2), amount: 1, recipient: signer, maxAmount: type(uint256).max});
    //
    //     OrderLib.CosignedOrder[] memory ros = new OrderLib.CosignedOrder[](1);
    //     ros[0] = _dummyCosignedOrder(address(token), 0);
    //     ros[0].outputs = outs;
    //
    //     vm.prank(address(reactor));
    //     vm.expectRevert(Executor.InvalidOrder.selector);
    //     exec.reactorCallback(
    //         ros,
    //         abi.encode(
    //             address(adapter),
    //             SettlementLib.Execution({
    //                 fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
    //                 minAmountOut: 0,
    //                 data: hex""
    //             })
    //         )
    //     );
    // }

    function test_reactorCallback_transfers_delta_to_swapper_when_outAmountSwapper_greater() public {
        ERC20Mock out = new ERC20Mock();
        _mint(address(out), address(exec), 100);

        OrderLib.CosignedOrder memory co = _dummyCosignedOrder(address(out), 500);
        bytes32 orderHash = OrderLib.hash(co.order);

        uint256 before = out.balanceOf(signer);
        vm.prank(address(reactor));
        exec.reactorCallback(
            orderHash,
            co,
            SettlementLib.Execution({
                minAmountOut: 600,
                fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
                data: hex""
            })
        );
        assertEq(out.balanceOf(signer), before + 100);
    }

    function test_e2e_execute_callback_and_surplus() public {
        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({reactor: address(reactor), swapper: signer, nonce: 1, deadline: 1_086_400});
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: ref, share: refShare, data: ""});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 100, maxAmount: 100});
        co.order.output = OrderLib.Output({token: address(tokenOut), amount: 500, maxAmount: 500, recipient: signer});

        // use CosignedOrder directly in execute

        _mint(address(tokenOut), address(exec), 1000);
        _mint(address(token), address(exec), 200);

        SettlementLib.Execution memory ex2 = SettlementLib.Execution({
            minAmountOut: 600,
            fee: OrderLib.Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });
        exec.execute(co, ex2);

        assertEq(IERC20(address(tokenOut)).allowance(address(exec), address(reactor)), 500);
        assertEq(tokenOut.balanceOf(ref), 90);
        assertEq(tokenOut.balanceOf(signer), 910);
        assertEq(token.balanceOf(ref), 20);
        assertEq(token.balanceOf(signer), 180);
        assertEq(tokenOut.balanceOf(address(exec)), 0);
        assertEq(token.balanceOf(address(exec)), 0);
    }

    function _dummyCosignedOrder(address outToken, uint256 outAmount)
        public
        view
        returns (OrderLib.CosignedOrder memory cosignedOrder)
    {
        return _dummyCosignedOrderWithRecipient(outToken, outAmount, signer);
    }

    function _dummyCosignedOrderWithRecipient(address outToken, uint256 outAmount, address recipient)
        public
        view
        returns (OrderLib.CosignedOrder memory cosignedOrder)
    {
        cosignedOrder.order.info =
            OrderLib.OrderInfo({reactor: address(reactor), swapper: signer, nonce: 0, deadline: 1_086_400});
        cosignedOrder.order.exchange =
            OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0, data: ""});
        cosignedOrder.order.executor = address(exec);
        cosignedOrder.order.epoch = 0;
        cosignedOrder.order.slippage = 0;
        cosignedOrder.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});

        cosignedOrder.order.output =
            OrderLib.Output({token: outToken, amount: outAmount, maxAmount: type(uint256).max, recipient: recipient});

        cosignedOrder.signature = bytes("");
        cosignedOrder.cosignature = bytes("");
    }

    function test_execution_with_gas_fee_fields() public {
        // Test that the new gas fee fields can be set and used
        address feeToken = address(token); // Use actual token for gas fee
        uint256 feeAmount = 1000;
        address feeRecipient = makeAddr("gasFeeRecipient");

        // Mint gas fee tokens to the executor
        _mint(feeToken, address(exec), feeAmount);

        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({reactor: address(reactor), swapper: signer, nonce: 0, deadline: 1_086_400});
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0, data: ""});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});

        SettlementLib.Execution memory ex = SettlementLib.Execution({
            minAmountOut: 0,
            fee: OrderLib.Output({token: feeToken, amount: feeAmount, recipient: feeRecipient, maxAmount: type(uint256).max}),
            data: hex""
        });

        uint256 balanceBefore = IERC20(feeToken).balanceOf(feeRecipient);
        exec.execute(co, ex);

        // Verify that gas fee was transferred to the recipient
        uint256 balanceAfter = IERC20(feeToken).balanceOf(feeRecipient);
        assertEq(balanceAfter, balanceBefore + feeAmount);
    }
}
