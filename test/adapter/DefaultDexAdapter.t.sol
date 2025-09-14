// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "test/base/BaseTest.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract DefaultDexAdapterTest is BaseTest {
    DefaultDexAdapter public adapterUut;
    MockDexRouter public router;
    // Use BaseTest.token and token2 across tests

    function setUp() public override {
        super.setUp();
        router = new MockDexRouter();
        adapterUut = new DefaultDexAdapter(address(router));
        // Pre-fund adapter with input token
        ERC20Mock(address(token)).mint(address(adapterUut), 1000 ether);

        // base defaults for this suite
        adapter = address(adapterUut);
    }

    function test_swap_ERC20_to_ERC20_success() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        OrderLib.CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), 1000 ether, address(token2), 2000 ether, signer
        );

        uint256 beforeBalance = ERC20Mock(address(token2)).balanceOf(signer);

        adapterUut.swap(cosignedOrder, data);

        // Check output token was minted to recipient
        assertEq(ERC20Mock(address(token2)).balanceOf(signer), beforeBalance + 2000 ether);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(router)), 0);
    }

    function test_swap_reverts_invalid_data() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        OrderLib.CosignedOrder memory cosignedOrder = order();

        bytes memory data = "invalid_call_data";

        // Invalid call data should revert
        vm.expectRevert();
        adapterUut.swap(cosignedOrder, data);
    }

    function test_swap_reverts_when_router_call_fails() public {
        router.setShouldFail(true);

        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;
        OrderLib.CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), 1000 ether, address(token2), 2000 ether, signer
        );

        vm.expectRevert("Mock swap failed");
        adapterUut.swap(cosignedOrder, data);
    }

    function test_swap_handles_USDT_like_tokens() public {
        // Use existing USDT mock
        USDTMock usdt = new USDTMock();
        usdt.mint(address(adapterUut), 1000 ether);

        inToken = address(usdt);
        inAmount = 1000 ether;
        inMax = inAmount;
        outToken = address(token2);
        outAmount = 500 ether;
        outMax = type(uint256).max;
        OrderLib.CosignedOrder memory cosignedOrder = order();

        // Pre-set a non-zero allowance to test forceApprove behavior
        vm.prank(address(adapterUut));
        usdt.approve(address(router), 1);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(usdt), 1000 ether, address(token2), 2000 ether, signer
        );

        // Should not revert despite USDT-like behavior
        adapterUut.swap(cosignedOrder, data);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(usdt.allowance(address(adapterUut), address(router)), 0);
    }
}
