// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Executor} from "src/Executor.sol";
import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {P2DexAdapter} from "src/adapter/P2DexAdapter.sol";
import {ParaswapDexAdapter} from "src/adapter/ParaswapDexAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {MockParaswapAugustus, MockTokenTransferProxy} from "test/mocks/MockParaswap.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";

contract MockResolvedAdapter is IExchangeAdapter {
    error UnexpectedResolvedAmount();
    error UnexpectedTarget();

    uint256 public immutable expectedResolvedAmountOut;
    address public immutable expectedTarget;

    constructor(uint256 _expectedResolvedAmountOut, address _expectedTarget) {
        expectedResolvedAmountOut = _expectedResolvedAmountOut;
        expectedTarget = _expectedTarget;
    }

    function delegateSwap(bytes32, uint256 resolvedAmountOut, CosignedOrder memory, Execution memory x)
        external
        view
        override
    {
        if (resolvedAmountOut != expectedResolvedAmountOut) revert UnexpectedResolvedAmount();
        if (x.target != expectedTarget) revert UnexpectedTarget();
    }
}

contract UniversalAdapterTest is BaseTest {
    UniversalAdapter public adapterUut;
    Executor public exec;
    MockReactor public reactorMock;
    MockDexRouter public router;
    MockPermit2 public permit2;
    MockTokenTransferProxy public tokenTransferProxy;
    MockParaswapAugustus public paraswapRouter;

    function setUp() public override {
        super.setUp();
        adapterUut = new UniversalAdapter();
        reactorMock = new MockReactor();
        exec = new Executor(address(reactorMock), wm);
        router = new MockDexRouter();
        permit2 = new MockPermit2();
        tokenTransferProxy = new MockTokenTransferProxy();
        paraswapRouter = new MockParaswapAugustus(tokenTransferProxy);

        reactor = address(reactorMock);
        executor = address(exec);
        adapter = address(adapterUut);
    }

    function test_delegateSwap_forwards_live_resolved_amount() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = 777 ether;
        MockResolvedAdapter selectedAdapter = new MockResolvedAdapter(resolvedAmountOut, address(router));

        Execution memory inner = executionWithTargetData(0, address(router), hex"1234");
        Execution memory x = _universalExecution(address(selectedAdapter), inner);

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

    function test_executor_routes_default_adapter_through_universal() public {
        DefaultDexAdapter defaultAdapter = new DefaultDexAdapter(address(router));

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        ERC20Mock(address(token)).mint(address(exec), inAmount);

        bytes memory routerData = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), inAmount, address(token2), 2000 ether, address(exec)
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory inner = executionWithTargetData(0, address(router), routerData);
        Execution memory outer = _universalExecution(address(defaultAdapter), inner);

        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, resolvedAmountOut, cosignedOrder, outer);

        assertEq(ERC20Mock(address(token)).balanceOf(address(router)), inAmount);
        assertEq(ERC20Mock(address(token2)).balanceOf(address(exec)), 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(exec), address(router)), 0);
        assertEq(ERC20Mock(address(token2)).allowance(address(exec), address(reactorMock)), resolvedAmountOut);
    }

    function test_executor_routes_paraswap_adapter_through_universal() public {
        ParaswapDexAdapter paraswapAdapter = new ParaswapDexAdapter(address(paraswapRouter));

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 600 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        ERC20Mock(address(token)).mint(address(exec), inAmount);

        bytes memory routerData = abi.encodeWithSelector(
            MockParaswapAugustus.doSwap.selector, address(token), inAmount, address(token2), 2000 ether, address(exec)
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory inner = executionWithTargetData(0, address(paraswapRouter), routerData);
        Execution memory outer = _universalExecution(address(paraswapAdapter), inner);

        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, resolvedAmountOut, cosignedOrder, outer);

        assertEq(ERC20Mock(address(token)).balanceOf(address(paraswapRouter)), inAmount);
        assertEq(ERC20Mock(address(token2)).balanceOf(address(exec)), 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(exec), address(tokenTransferProxy)), 0);
        assertEq(ERC20Mock(address(token2)).allowance(address(exec), address(reactorMock)), resolvedAmountOut);
    }

    function test_executor_routes_p2_adapter_through_universal() public {
        P2DexAdapter p2Adapter = new P2DexAdapter(address(router), address(permit2));

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        ERC20Mock(address(token)).mint(address(exec), inAmount);

        bytes memory routerData = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), inAmount, address(token2), 2000 ether, address(exec)
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory inner = executionWithTargetData(0, address(router), routerData);
        Execution memory outer = _universalExecution(address(p2Adapter), inner);

        vm.prank(address(reactorMock));
        exec.reactorCallback(hash, resolvedAmountOut, cosignedOrder, outer);

        assertEq(ERC20Mock(address(token)).balanceOf(address(router)), inAmount);
        assertEq(ERC20Mock(address(token2)).balanceOf(address(exec)), 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(exec), address(router)), 0);
        assertEq(ERC20Mock(address(token)).allowance(address(exec), address(permit2)), 0);
        assertEq(ERC20Mock(address(token2)).allowance(address(exec), address(reactorMock)), resolvedAmountOut);
        assertEq(permit2.approveCallCount(), 1);

        (address approvedToken, address approvedSpender, uint160 amount, uint48 expiration) = permit2.lastApproval();
        assertEq(approvedToken, address(token));
        assertEq(approvedSpender, address(router));
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
    }

    function _universalExecution(address selectedAdapter, Execution memory inner)
        internal
        pure
        returns (Execution memory outer)
    {
        outer = executionWithTargetData(inner.minAmountOut, selectedAdapter, abi.encode(inner));
    }
}
