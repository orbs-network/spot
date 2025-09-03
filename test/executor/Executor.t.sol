// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";

import {Executor} from "src/executor/Executor.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {IReactorCallback} from "src/lib/uniswapx/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {
    ResolvedOrder, SignedOrder, OrderInfo, InputToken, OutputToken
} from "src/lib/uniswapx/base/ReactorStructs.sol";
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

    function _soFrom(OrderLib.CosignedOrder memory co) internal pure returns (SignedOrder memory so) {
        so.order = abi.encode(co);
        so.sig = hex"";
    }

    function test_execute_forwards_to_reactor_with_callback() public {
        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: address(0),
            additionalValidationData: abi.encode(address(0), uint16(0))
        });
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});
        SettlementLib.Execution memory ex = SettlementLib.Execution({
            fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
            minAmountOut: 0,
            data: hex""
        });
        exec.execute(co, ex);

        assertEq(reactor.lastSender(), address(exec));
        (bytes memory lastOrderBytes,) = reactor.lastOrder();
        assertEq(keccak256(lastOrderBytes), keccak256(abi.encode(co)));
        assertEq(
            keccak256(reactor.lastCallbackData()),
            keccak256(
                abi.encode(
                    address(adapter),
                    SettlementLib.Execution({
                        fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                        minAmountOut: 0,
                        data: hex""
                    })
                )
            )
        );
    }

    function test_execute_reverts_when_not_allowed() public {
        disallowThis();

        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: address(0),
            additionalValidationData: abi.encode(address(0), uint16(0))
        });
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});
        SettlementLib.Execution memory ex = SettlementLib.Execution({
            fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
            minAmountOut: 0,
            data: hex""
        });
        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.execute(co, ex);
    }

    function test_reactorCallback_onlyReactor() public {
        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 0);

        vm.expectRevert(abi.encodeWithSelector(Executor.InvalidSender.selector));
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
        );
    }

    function test_reactorCallback_executes_multicall_and_sets_erc20_approval() public {
        // mint to executor
        _mint(address(token), address(exec), 1e18);

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(token), 1234);

        // call from reactor
        vm.prank(address(reactor));
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
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
        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(usdt), 1234);

        // call from reactor; should internally forceApprove to exact amount (approve(0) then approve(1234))
        vm.prank(address(reactor));
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
        );

        // final allowance set to exact amount
        assertEq(IERC20(address(usdt)).allowance(address(exec), address(reactor)), 1234);
    }

    function test_reactorCallback_handles_eth_output_and_sends_to_reactor() public {
        // fund executor to cover sendValue
        vm.deal(address(exec), 1 ether);

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(0), 987);

        uint256 beforeBal = address(reactor).balance;
        vm.prank(address(reactor));
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
        );
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
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
        );
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
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 0,
                    data: hex""
                })
            )
        );
    }

    function test_reactorCallback_transfers_delta_to_swapper_when_outAmountSwapper_greater() public {
        ERC20Mock out = new ERC20Mock();
        _mint(address(out), address(exec), 100);

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);
        ros[0] = _dummyResolvedOrder(address(out), 500);

        uint256 before = out.balanceOf(signer);
        vm.prank(address(reactor));
        exec.reactorCallback(
            ros,
            abi.encode(
                address(adapter),
                SettlementLib.Execution({
                    fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
                    minAmountOut: 600,
                    data: hex""
                })
            )
        );
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
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: ref, share: refShare});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 100, maxAmount: 100});
        co.order.output = OrderLib.Output({token: address(tokenOut), amount: 500, maxAmount: 500, recipient: signer});

        // use CosignedOrder directly in execute

        _mint(address(tokenOut), address(exec), 1000);
        _mint(address(token), address(exec), 200);

        SettlementLib.Execution memory ex2 = SettlementLib.Execution({
            fee: OutputToken({token: address(0), amount: 0, recipient: address(0)}),
            minAmountOut: 600,
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
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});

        so.order = abi.encode(co);
        so.sig = hex"";
    }

    function _dummyResolvedOrder(address outToken, uint256 outAmount) public view returns (ResolvedOrder memory ro) {
        OrderInfo memory info = OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: IValidationCallback(address(0)),
            additionalValidationData: abi.encode(address(0))
        });
        InputToken memory input = InputToken({token: address(token), amount: 0, maxAmount: 0});

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({token: outToken, amount: outAmount, recipient: signer});

        ro = ResolvedOrder({info: info, input: input, outputs: outputs, sig: bytes(""), hash: bytes32(uint256(123))});
    }

    function test_execution_with_gas_fee_fields() public {
        // Test that the new gas fee fields can be set and used
        address gasFeeToken = address(token); // Use actual token for gas fee
        uint256 gasFeeAmount = 1000;
        address gasFeeRecipient = makeAddr("gasFeeRecipient");

        // Mint gas fee tokens to the executor
        _mint(gasFeeToken, address(exec), gasFeeAmount);

        OrderLib.CosignedOrder memory co;
        co.order.info = OrderLib.OrderInfo({
            reactor: address(reactor),
            swapper: signer,
            nonce: 0,
            deadline: 1_086_400,
            additionalValidationContract: address(0),
            additionalValidationData: abi.encode(address(0), uint16(0))
        });
        co.order.exchange = OrderLib.Exchange({adapter: address(adapter), ref: address(0), share: 0});
        co.order.executor = address(exec);
        co.order.epoch = 0;
        co.order.slippage = 0;
        co.order.input = OrderLib.Input({token: address(token), amount: 0, maxAmount: 0});
        co.order.output = OrderLib.Output({token: address(token), amount: 0, maxAmount: 0, recipient: signer});

        SettlementLib.Execution memory ex = SettlementLib.Execution({
            fee: OutputToken({token: gasFeeToken, amount: gasFeeAmount, recipient: gasFeeRecipient}),
            minAmountOut: 0,
            data: hex""
        });

        uint256 beforeBalance = IERC20(gasFeeToken).balanceOf(gasFeeRecipient);
        exec.execute(co, ex);

        // Verify that the gas fee fields are properly encoded in the callback data
        assertEq(reactor.lastSender(), address(exec));
        (bytes memory lastOrderBytes,) = reactor.lastOrder();
        assertEq(keccak256(lastOrderBytes), keccak256(abi.encode(co)));

        // The callback data should include our gas fee fields
        bytes memory expectedCallbackData = abi.encode(address(adapter), ex);
        assertEq(keccak256(reactor.lastCallbackData()), keccak256(expectedCallbackData));

        // Verify that gas fee was transferred to the recipient
        uint256 afterBalance = IERC20(gasFeeToken).balanceOf(gasFeeRecipient);
        assertEq(afterBalance, beforeBalance + gasFeeAmount);
    }
}
