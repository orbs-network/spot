// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {ParaswapDexAdapter} from "src/adapter/ParaswapDexAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockParaswapAugustus, MockTokenTransferProxy} from "test/mocks/MockParaswap.sol";

contract ParaswapDexAdapterTest is BaseTest {
    ParaswapDexAdapter public adapterUut;
    MockParaswapAugustus public router;
    MockTokenTransferProxy public tokenTransferProxy;

    function setUp() public override {
        super.setUp();

        tokenTransferProxy = new MockTokenTransferProxy();
        router = new MockParaswapAugustus(tokenTransferProxy);
        adapterUut = new ParaswapDexAdapter(address(router));

        ERC20Mock(address(token)).mint(address(adapterUut), 1000 ether);

        adapter = address(adapterUut);
    }

    function test_swap_success() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 600 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockParaswapAugustus.doSwap.selector, address(token), inAmount, address(token2), 2000 ether, signer
        );

        uint256 beforeBalance = ERC20Mock(address(token2)).balanceOf(signer);

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(ERC20Mock(address(token2)).balanceOf(signer), beforeBalance + 2000 ether);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(tokenTransferProxy)), 0);
    }

    function test_swap_reverts_invalid_data() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 600 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = "invalid";

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert();
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function test_swap_reverts_when_router_fails() public {
        router.setShouldFail(true);

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 600 ether;
        outMax = type(uint256).max;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockParaswapAugustus.doSwap.selector, address(token), inAmount, address(token2), 2000 ether, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert("Mock ParaSwap swap failed");
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

        hoax(address(adapterUut));
        usdt.approve(address(tokenTransferProxy), 1);

        bytes memory data = abi.encodeWithSelector(
            MockParaswapAugustus.doSwap.selector, address(usdt), inAmount, address(token2), 2000 ether, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithData(0, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(usdt.allowance(address(adapterUut), address(tokenTransferProxy)), 0);
    }
}
