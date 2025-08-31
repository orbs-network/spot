// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";

import {Executor, IMulticall3} from "src/executor/Executor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {IReactorCallback} from "src/lib/uniswapx/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {ResolvedOrder, SignedOrder, OrderInfo, InputToken, OutputToken, ERC20} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";

contract ExecutorTest is BaseTest {
    Executor public exec;
    MockReactor public reactor;
    ERC20Mock public tokenOut;
    address public ref;
    uint16 public refShare = 1000; // 10% in bps

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);

        reactor = new MockReactor();
        exec = new Executor(multicall, address(reactor), wm);

        tokenOut = new ERC20Mock();
        ref = makeAddr("ref");

        // allow this test as caller
        allowThis();
    }

    function _mintCall(address tkn, address to, uint256 amt) internal pure returns (IMulticall3.Call memory c) {
        return IMulticall3.Call({target: tkn, callData: abi.encodeWithSignature("mint(address,uint256)", to, amt)});
    }

    function _soFrom(OrderLib.CosignedOrder memory co) internal pure returns (SignedOrder memory so) {
        so.order = abi.encode(co);
        so.sig = hex"";
    }

    function test_execute_forwards_to_reactor_with_callback() public {
        SignedOrder memory so = _dummySignedOrder();
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](0);

        exec.execute(so, calls, 0);

        assertEq(reactor.lastSender(), address(exec));
        (bytes memory lastOrderBytes,) = reactor.lastOrder();
        assertEq(keccak256(lastOrderBytes), keccak256(so.order));
        assertEq(keccak256(reactor.lastCallbackData()), keccak256(abi.encode(calls, 0)));
    }

    function test_execute_reverts_when_not_allowed() public {
        disallowThis();

        SignedOrder memory so = _dummySignedOrder();
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](0);

        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.execute(so, calls, 0);
    }

    function test_reactorCallback_onlyReactor() public {
        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 0);
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](0);

        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.reactorCallback(ros, abi.encode(calls, 0));
    }

    function test_reactorCallback_executes_multicall_and_sets_erc20_approval() public {
        // prepare multicall to mint to executor
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = _mintCall(address(token), address(exec), 1e18);

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 1234);

        // call from reactor
        vm.prank(address(reactor));
        exec.reactorCallback(ros, abi.encode(calls, 0));

        // multicall executed: executor now holds minted tokens
        assertEq(ERC20Mock(address(token)).balanceOf(address(exec)), 1e18);

        // approval set for reactor to allowance + amount
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactor)), 1234);
    }

    function test_reactorCallback_handles_usdt_like_tokens_approve_zero_first() public {
        // deploy USDT-like token that reverts on non-zero->non-zero approvals
        USDTMock usdt = new USDTMock();

        // pre-set a non-zero allowance from executor to reactor
        vm.prank(address(exec));
        usdt.approve(address(reactor), 1);

        // mint to executor via multicall
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = _mintCall(address(usdt), address(exec), 1e18);

        // resolved order outputs USDT to reactor via approval path
        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(usdt), 1234);

        // call from reactor; should internally approve(0) then approve(1+1234)
        vm.prank(address(reactor));
        exec.reactorCallback(ros, abi.encode(calls, 0));

        // final allowance == previous (1) + amount (1234)
        assertEq(IERC20(address(usdt)).allowance(address(exec), address(reactor)), 1235);
    }

    function test_reactorCallback_handles_eth_output_and_sends_to_reactor() public {
        // fund executor to cover sendValue
        vm.deal(address(exec), 1 ether);

        IMulticall3.Call[] memory calls = new IMulticall3.Call[](0);
        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(0), 987);

        uint256 beforeBal = address(reactor).balance;
        vm.prank(address(reactor));
        exec.reactorCallback(ros, abi.encode(calls, 0));
        assertEq(address(reactor).balance, beforeBal + 987);
    }

    function test_validate_allows_only_self_as_filler() public view {
        exec.validate(address(exec), _dummyResolvedOrder(address(token), 0));
    }

    function test_validate_reverts_for_others() public {
        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.validate(other, _dummyResolvedOrder(address(token), 0));
    }

    function test_reactorCallback_allows_single_output_to_non_swapper() public {
        OutputToken[] memory outs = new OutputToken[](1);
        outs[0] = OutputToken({token: address(token), amount: 100, recipient: other});

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 0);
        ros[0].outputs = outs;

        // should not revert; also sets approval for reactor
        vm.prank(address(reactor));
        exec.reactorCallback(ros, abi.encode(new IMulticall3.Call[](0), 0));
        assertEq(IERC20(address(token)).allowance(address(exec), address(reactor)), 100);
    }

    function test_reactorCallback_reverts_on_mixed_out_tokens_to_swapper() public {
        ERC20Mock token2 = new ERC20Mock();
        OutputToken[] memory outs = new OutputToken[](2);
        outs[0] = OutputToken({token: address(token), amount: 100, recipient: signer});
        outs[1] = OutputToken({token: address(token2), amount: 1, recipient: signer});

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 0);
        ros[0].outputs = outs;

        vm.prank(address(reactor));
        vm.expectRevert(Executor.InvalidOrder.selector);
        exec.reactorCallback(ros, abi.encode(new IMulticall3.Call[](0), 0));
    }

    function test_reactorCallback_transfers_delta_to_swapper_when_outAmountSwapper_greater() public {
        ERC20Mock out = new ERC20Mock();
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = _mintCall(address(out), address(exec), 100);

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(out), 500);

        uint256 before = out.balanceOf(signer);
        vm.prank(address(reactor));
        exec.reactorCallback(ros, abi.encode(calls, 600));
        assertEq(out.balanceOf(signer), before + 100);
    }

    function test_e2e_execute_callback_and_surplus() public {
        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 1,
            deadline: 1_086_400,
            additionalValidationContract: address(0),
            additionalValidationData: abi.encode(ref, refShare)
        });
        co.order.exclusiveFiller = address(exec);
        co.order.exclusivityOverrideBps = 0;
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 100, maxAmount: 100});
        co.order.output = OrderLib.Output({token: address(tokenOut), amount: 500, maxAmount: 500, recipient: signer});

        SignedOrder memory so = _soFrom(co);

        IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
        calls[0] = _mintCall(address(tokenOut), address(exec), 1000);
        calls[1] = _mintCall(address(token), address(exec), 200);

        exec.execute(so, calls, 600);

        assertEq(IERC20(address(tokenOut)).allowance(address(exec), address(reactor)), 500);
        assertEq(tokenOut.balanceOf(ref), 90);
        assertEq(tokenOut.balanceOf(signer), 910);
        assertEq(token.balanceOf(ref), 20);
        assertEq(token.balanceOf(signer), 180);
        assertEq(tokenOut.balanceOf(address(exec)), 0);
        assertEq(token.balanceOf(address(exec)), 0);
    }

    function _dummySignedOrder() public view returns (SignedOrder memory so) {
        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: address(0),
            additionalValidationData: abi.encode(address(0), uint16(0))
        });
        co.order.exclusiveFiller = address(exec);
        co.order.exclusivityOverrideBps = 0;
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});

        so.order = abi.encode(co);
        so.sig = hex"";
    }

    function _dummyResolvedOrder(address outToken, uint256 outAmount) public view returns (ResolvedOrder memory ro) {
        OrderInfo memory info = OrderInfo({
            reactor: IReactor(address(reactor)),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: IValidationCallback(address(0)),
            additionalValidationData: abi.encode(address(0))
        });
        InputToken memory input = InputToken({token: ERC20(address(token)), amount: 0, maxAmount: 0});

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({token: outToken, amount: outAmount, recipient: signer});

        ro = ResolvedOrder({info: info, input: input, outputs: outputs, sig: bytes(""), hash: bytes32(uint256(123))});
    }
}
