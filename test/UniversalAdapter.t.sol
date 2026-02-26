// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract UniversalAdapterTest is BaseTest {
    UniversalAdapter public adapterUut;
    MockDexRouter public router;

    function setUp() public override {
        super.setUp();
        adapterUut = new UniversalAdapter();
        router = new MockDexRouter();
        ERC20Mock(address(token)).mint(address(adapterUut), 1000 ether);
        adapter = address(adapterUut);
    }

    function test_swap_success() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), 1000 ether, address(token2), 2000 ether, signer
        );

        uint256 beforeBalance = ERC20Mock(address(token2)).balanceOf(signer);

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithTargetData(0, address(router), data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(ERC20Mock(address(token2)).balanceOf(signer), beforeBalance + 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(router)), 0);
    }

    function test_swap_reverts_invalid_target() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert(IExchangeAdapter.InvalidTarget.selector);
        Execution memory x = executionWithTargetData(0, address(0), hex"");
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function test_swap_reverts_when_target_call_fails() public {
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
        Execution memory x = executionWithTargetData(0, address(router), data);
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

        hoax(address(adapterUut));
        usdt.approve(address(router), 1);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(usdt), 1000 ether, address(token2), 2000 ether, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithTargetData(0, address(router), data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(usdt.allowance(address(adapterUut), address(router)), 0);
    }
}
