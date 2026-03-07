// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Executor} from "src/Executor.sol";
import {Settler} from "src/ops/Settler.sol";
import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {RePermit} from "src/RePermit.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";
import {WrappedNativeMock} from "test/mocks/WrappedNativeMock.sol";

contract SettlerTest is BaseTest {
    Executor public exec;
    MockReactor public reactorMock;
    Settler public settlerUut;
    UniversalAdapter public universalAdapterUut;
    WrappedNativeMock public wrappedNative;

    address public solver;
    uint256 public solverPk;

    function setUp() public override {
        super.setUp();
        reactorMock = new MockReactor();
        exec = new Executor(address(reactorMock), wm);
        wrappedNative = new WrappedNativeMock();
        settlerUut = new Settler(repermit, address(wrappedNative));
        universalAdapterUut = new UniversalAdapter();

        reactor = address(reactorMock);
        executor = address(exec);
        adapter = address(universalAdapterUut);

        (solver, solverPk) = makeAddrAndKey("solver");
    }

    function test_settler_pulls_output_and_pays_solver() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100 ether;
        inMax = inAmount;
        outAmount = 55 ether;
        triggerUpper = 0;
        CosignedOrder memory co = order();

        bytes32 hash = OrderLib.hash(co.order);
        uint256 outputAmount = co.order.output.limit;
        bytes memory solverSig = _solverSignature(co, co.order.output.token, outputAmount, address(settlerUut));

        ERC20Mock(outToken).mint(solver, outputAmount);
        hoax(solver);
        ERC20Mock(outToken).approve(repermit, outputAmount);

        ERC20Mock(inToken).mint(address(exec), inAmount);

        Execution memory x = _executionViaUniversal(co, solver, outputAmount, solverSig);
        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, outputAmount, co, x);

        assertEq(ERC20Mock(inToken).balanceOf(solver), inAmount);
        assertEq(ERC20Mock(outToken).balanceOf(address(exec)), outputAmount);
        assertEq(ERC20Mock(inToken).allowance(address(exec), address(settlerUut)), 0);
        assertEq(ERC20Mock(outToken).allowance(address(exec), address(reactorMock)), outputAmount);
    }

    function test_settler_reverts_invalid_target() public {
        CosignedOrder memory co = order();
        bytes32 hash = OrderLib.hash(co.order);

        Execution memory settlerExecution = executionWithTargetData(0, address(0), abi.encode(uint256(0), bytes("")));
        bytes memory data = abi.encodeWithSelector(Settler.swap.selector, co, settlerExecution);
        Execution memory x = executionWithTargetData(0, address(settlerUut), data);
        vm.expectRevert(Settler.InvalidTarget.selector);
        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, 0, co, x);
    }

    function test_settler_reverts_when_used_as_adapter() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100 ether;
        inMax = inAmount;
        outAmount = 55 ether;
        triggerUpper = 0;
        adapter = address(settlerUut);
        CosignedOrder memory co = order();

        bytes32 hash = OrderLib.hash(co.order);
        uint256 outputAmount = co.order.output.limit;
        bytes memory solverSig = _solverSignature(co, co.order.output.token, outputAmount, address(settlerUut));
        Execution memory x = executionWithTargetData(outputAmount, solver, abi.encode(outputAmount, solverSig));

        vm.expectRevert();
        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, outputAmount, co, x);
    }

    function test_settler_reverts_invalid_signature() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100 ether;
        inMax = inAmount;
        outAmount = 55 ether;
        triggerUpper = 0;
        CosignedOrder memory co = order();

        bytes32 hash = OrderLib.hash(co.order);
        uint256 outputAmount = co.order.output.limit;
        bytes32 digest = IEIP712(repermit)
            .hashTypedData(
                hashRePermit(
                    co.order.output.token,
                    outputAmount,
                    co.order.nonce,
                    co.order.deadline,
                    hash,
                    OrderLib.WITNESS_TYPE_SUFFIX,
                    address(settlerUut)
                )
            );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);
        bytes memory wrongSig = bytes.concat(r, s, bytes1(v));

        ERC20Mock(outToken).mint(solver, outputAmount);
        hoax(solver);
        ERC20Mock(outToken).approve(repermit, outputAmount);
        ERC20Mock(inToken).mint(address(exec), inAmount);

        Execution memory x = _executionViaUniversal(co, solver, outputAmount, wrongSig);

        vm.expectRevert(RePermit.InvalidSignature.selector);
        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, outputAmount, co, x);
    }

    function test_settler_native_output_with_wrapped_token() public {
        inToken = address(token);
        outToken = address(0);
        inAmount = 100 ether;
        inMax = inAmount;
        outAmount = 1 ether;
        triggerUpper = 0;
        CosignedOrder memory co = order();

        bytes32 hash = OrderLib.hash(co.order);
        uint256 outputAmount = co.order.output.limit;
        bytes memory solverSig = _solverSignature(co, address(wrappedNative), outputAmount, address(settlerUut));

        vm.deal(solver, outputAmount);
        vm.startPrank(solver);
        wrappedNative.deposit{value: outputAmount}();
        wrappedNative.approve(repermit, outputAmount);
        vm.stopPrank();

        ERC20Mock(inToken).mint(address(exec), inAmount);

        uint256 beforeReactorBalance = address(reactorMock).balance;
        Execution memory x = _executionViaUniversal(co, solver, outputAmount, solverSig);

        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, outputAmount, co, x);

        assertEq(address(reactorMock).balance, beforeReactorBalance + outputAmount);
        assertEq(ERC20Mock(inToken).balanceOf(solver), inAmount);
    }

    function _executionViaUniversal(
        CosignedOrder memory co,
        address solverAddress,
        uint256 outputAmount,
        bytes memory solverSig
    ) internal view returns (Execution memory x) {
        Execution memory settlerExecution = executionWithTargetData(
            outputAmount, solverAddress, abi.encode(outputAmount, solverSig)
        );
        bytes memory data = abi.encodeWithSelector(Settler.swap.selector, co, settlerExecution);
        x = executionWithTargetData(outputAmount, address(settlerUut), data);
    }

    function _solverSignature(CosignedOrder memory co, address permitToken, uint256 amount, address spender)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 digest = IEIP712(repermit)
            .hashTypedData(
                hashRePermit(
                    permitToken,
                    amount,
                    co.order.nonce,
                    co.order.deadline,
                    OrderLib.hash(co.order),
                    OrderLib.WITNESS_TYPE_SUFFIX,
                    spender
                )
            );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverPk, digest);
        sig = bytes.concat(r, s, bytes1(v));
    }
}
