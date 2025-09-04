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

    function _createOrder(address inputToken, uint256 inputAmount, address outputToken)
        internal
        view
        returns (OrderLib.ResolvedOrder memory order)
    {
        order.input = OrderLib.InputToken({token: inputToken, amount: inputAmount, maxAmount: inputAmount});

        OrderLib.OutputToken[] memory outputs = new OrderLib.OutputToken[](1);
        outputs[0] = OrderLib.OutputToken({
            token: outputToken,
            amount: 500 ether, // min output
            recipient: recipient
        });
        order.outputs = outputs;

        order.info = OrderLib.OrderInfo({
            reactor: address(0),
            swapper: user,
            nonce: 1,
            deadline: block.timestamp + 1000,
            additionalValidationContract: address(0),
            additionalValidationData: ""
        });
    }

    function test_swap_ERC20_to_ERC20_success() public {
        OrderLib.ResolvedOrder memory order = _createOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(tokenA), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        uint256 beforeBalance = tokenB.balanceOf(recipient);

        adapter.swap(order, data);

        // Check output token was minted to recipient
        assertEq(tokenB.balanceOf(recipient), beforeBalance + 2000 ether);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(tokenA.allowance(address(adapter), address(router)), 0);
    }

    function test_swap_reverts_invalid_data() public {
        OrderLib.ResolvedOrder memory order = _createOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = "invalid_call_data";

        // Invalid call data should revert
        vm.expectRevert();
        adapter.swap(order, data);
    }

    function test_swap_reverts_when_router_call_fails() public {
        router.setShouldFail(true);

        OrderLib.ResolvedOrder memory order = _createOrder(address(tokenA), 1000 ether, address(tokenB));

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(tokenA), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        vm.expectRevert("Mock swap failed");
        adapter.swap(order, data);
    }

    function test_swap_handles_USDT_like_tokens() public {
        // Use existing USDT mock
        USDTMock usdt = new USDTMock();
        usdt.mint(address(adapter), 1000 ether);

        OrderLib.ResolvedOrder memory order = _createOrder(address(usdt), 1000 ether, address(tokenB));

        // Pre-set a non-zero allowance to test forceApprove behavior
        vm.prank(address(adapter));
        usdt.approve(address(router), 1);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(usdt), 1000 ether, address(tokenB), 2000 ether, recipient
        );

        // Should not revert despite USDT-like behavior
        adapter.swap(order, data);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(usdt.allowance(address(adapter), address(router)), 0);
    }
}
