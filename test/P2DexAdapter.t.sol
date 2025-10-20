// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {P2DexAdapter} from "src/adapter/P2DexAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";

contract P2DexAdapterTest is BaseTest {
    P2DexAdapter public adapterUut;
    MockDexRouter public router;
    MockPermit2 public permit2;

    function setUp() public override {
        super.setUp();
        router = new MockDexRouter();
        permit2 = new MockPermit2();
        adapterUut = new P2DexAdapter(address(router), address(permit2));

        vm.label(address(permit2), "permit2");

        ERC20Mock(address(token)).mint(address(adapterUut), 1000 ether);

        adapter = address(adapterUut);
    }

    function test_swap_ERC20_to_ERC20_success() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), 1000 ether, address(token2), 2000 ether, signer
        );

        vm.prank(address(adapterUut));
        ERC20Mock(address(token)).approve(address(permit2), 1);
        vm.prank(address(adapterUut));
        ERC20Mock(address(token)).approve(address(router), 1);

        uint256 beforeBalance = ERC20Mock(address(token2)).balanceOf(signer);

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(ERC20Mock(address(token2)).balanceOf(signer), beforeBalance + 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(router)), 0);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(permit2)), 0);

        assertEq(permit2.approveCallCount(), 1);
        (address approvedToken, address approvedSpender, uint160 amount, uint48 expiration) = permit2.lastApproval();
        assertEq(approvedToken, address(token));
        assertEq(approvedSpender, address(router));
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
    }

    function test_swap_reverts_invalid_data() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = "invalid_call_data";

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert();
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function test_swap_reverts_when_router_call_fails() public {
        router.setShouldFail(true);

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), 1000 ether, address(token2), 2000 ether, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert("Mock swap failed");
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function test_swap_handles_USDT_like_tokens() public {
        USDTMock usdt = new USDTMock();
        usdt.mint(address(adapterUut), 1000 ether);

        inToken = address(usdt);
        inAmount = 1000 ether;
        inMax = inAmount;
        outToken = address(token2);
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        vm.prank(address(adapterUut));
        usdt.approve(address(router), 1);
        vm.prank(address(adapterUut));
        usdt.approve(address(permit2), 1);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(usdt), 1000 ether, address(token2), 2000 ether, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(usdt.allowance(address(adapterUut), address(router)), 0);
        assertEq(usdt.allowance(address(adapterUut), address(permit2)), 0);

        assertEq(permit2.approveCallCount(), 1);
        (address approvedToken, address approvedSpender, uint160 amount, uint48 expiration) = permit2.lastApproval();
        assertEq(approvedToken, address(usdt));
        assertEq(approvedSpender, address(router));
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
    }
}
