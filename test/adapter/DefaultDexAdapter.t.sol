// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IValidationCallback} from "src/interface/IValidationCallback.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract DefaultDexAdapterTest is Test {
    DefaultDexAdapter public adapter;
    MockDexRouter public router;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        router = new MockDexRouter();
        adapter = new DefaultDexAdapter(address(router));
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        // Fund the adapter with tokens for testing
        tokenA.mint(address(adapter), 1000 ether);
    }

    function _createCosignedOrder(address inputToken, uint256 inputAmount, address outputToken)
        internal
        view
        returns (OrderLib.CosignedOrder memory cosignedOrder)
    {
        cosignedOrder.order.input = OrderLib.Input({token: inputToken, amount: inputAmount, maxAmount: inputAmount});

        cosignedOrder.order.output = OrderLib.Output({
            token: outputToken,
            amount: 500 ether, // min output
            maxAmount: type(uint256).max, // no trigger
            recipient: recipient
        });

        cosignedOrder.order.reactor = address(0);
        cosignedOrder.order.swapper = user;
        cosignedOrder.order.nonce = 1;
        cosignedOrder.order.deadline = block.timestamp + 1000;
        cosignedOrder.order.additionalValidationContract = address(0);
        cosignedOrder.order.additionalValidationData = "";

        // Add minimal required fields for CosignedOrder
        cosignedOrder.signature = "";
        cosignedOrder.cosignature = "";
    }

    function test_swap_ERC20_to_ERC20_success() public {
        OrderLib.CosignedOrder memory cosignedOrder = _createCosignedOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(tokenA), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        uint256 beforeBalance = tokenB.balanceOf(recipient);

        adapter.swap(cosignedOrder, data);

        // Check output token was minted to recipient
        assertEq(tokenB.balanceOf(recipient), beforeBalance + 2000 ether);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(tokenA.allowance(address(adapter), address(router)), 0);
    }

    function test_swap_reverts_invalid_data() public {
        OrderLib.CosignedOrder memory cosignedOrder = _createCosignedOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = "invalid_call_data";

        // Invalid call data should revert
        vm.expectRevert();
        adapter.swap(cosignedOrder, data);
    }

    function test_swap_reverts_when_router_call_fails() public {
        router.setShouldFail(true);

        OrderLib.CosignedOrder memory cosignedOrder = _createCosignedOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(tokenA), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        vm.expectRevert("Mock swap failed");
        adapter.swap(cosignedOrder, data);
    }

    function test_swap_handles_USDT_like_tokens() public {
        // Use existing USDT mock
        USDTMock usdt = new USDTMock();
        usdt.mint(address(adapter), 1000 ether);

        OrderLib.CosignedOrder memory cosignedOrder = _createCosignedOrder(address(usdt), 1000 ether, address(tokenB));

        // Pre-set a non-zero allowance to test forceApprove behavior
        vm.prank(address(adapter));
        usdt.approve(address(router), 1);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(usdt), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        // Should not revert despite USDT-like behavior
        adapter.swap(cosignedOrder, data);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(usdt.allowance(address(adapter), address(router)), 0);
    }
}
