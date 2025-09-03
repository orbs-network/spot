// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {ResolvedOrder, InputToken, OutputToken, OrderInfo} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock router for testing
contract MockDexRouter {
    bool public shouldFail;
    uint256 public lastAmountIn;
    address public lastTokenIn;
    address public lastTokenOut;
    uint256 public outputAmount = 1000; // Default output amount

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setOutputAmount(uint256 _amount) external {
        outputAmount = _amount;
    }

    // Mock swap function for ERC20 -> ERC20
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        if (shouldFail) revert("Mock swap failed");

        lastAmountIn = amountIn;
        lastTokenIn = path[0];
        lastTokenOut = path[path.length - 1];

        // Transfer input tokens from caller
        IERC20(lastTokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Mint output tokens to recipient
        ERC20Mock(lastTokenOut).mint(to, outputAmount);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = outputAmount;
    }

    receive() external payable {}
}

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
        tokenA.mint(address(adapter), 10000e18);
        vm.deal(address(adapter), 10 ether);
    }

    function _createOrder(address inputToken, uint256 inputAmount, address outputToken)
        internal
        view
        returns (ResolvedOrder memory order)
    {
        order.input = InputToken({token: inputToken, amount: inputAmount, maxAmount: inputAmount});

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({
            token: outputToken,
            amount: 500, // min output
            recipient: recipient
        });
        order.outputs = outputs;

        order.info = OrderInfo({
            reactor: address(0),
            swapper: user,
            nonce: 1,
            deadline: block.timestamp + 1000,
            additionalValidationContract: IValidationCallback(address(0)),
            additionalValidationData: ""
        });
    }

    function test_swap_ERC20_to_ERC20_success() public {
        ResolvedOrder memory order = _createOrder(address(tokenA), 1000, address(tokenB));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.swapExactTokensForTokens.selector, 1000, 500, path, recipient, block.timestamp + 1000
        );

        uint256 beforeBalance = tokenB.balanceOf(recipient);

        adapter.swap(order, data);

        // Check output token was minted to recipient
        assertEq(tokenB.balanceOf(recipient), beforeBalance + router.outputAmount());

        // Check router received input tokens
        assertEq(router.lastAmountIn(), 1000);
        assertEq(router.lastTokenIn(), address(tokenA));
        assertEq(router.lastTokenOut(), address(tokenB));

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(tokenA.allowance(address(adapter), address(router)), 0);
    }

    function test_swap_reverts_invalid_router() public {
        ResolvedOrder memory order = _createOrder(address(tokenA), 1000, address(tokenB));

        bytes memory data = "invalid_call_data";

        // Invalid call data should revert with function selector not found
        vm.expectRevert();
        adapter.swap(order, data);
    }

    function test_swap_reverts_when_router_call_fails() public {
        router.setShouldFail(true);

        ResolvedOrder memory order = _createOrder(address(tokenA), 1000, address(tokenB));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.swapExactTokensForTokens.selector, 1000, 500, path, recipient, block.timestamp + 1000
        );

        // Address.functionCall will revert with "Address: low-level call failed" when the call reverts
        vm.expectRevert("Mock swap failed");
        adapter.swap(order, data);
    }

    function test_swap_handles_USDT_like_tokens() public {
        // Deploy USDT-like token that reverts on non-zero -> non-zero approvals
        USDTLikeToken usdt = new USDTLikeToken();
        usdt.mint(address(adapter), 10000e18);

        ResolvedOrder memory order = _createOrder(address(usdt), 1000, address(tokenB));

        // Pre-set a non-zero allowance to test forceApprove behavior
        vm.prank(address(adapter));
        usdt.approve(address(router), 1);

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(tokenB);

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.swapExactTokensForTokens.selector, 1000, 500, path, recipient, block.timestamp + 1000
        );

        // Should not revert despite USDT-like behavior
        adapter.swap(order, data);

        // After swap, allowance should be 0 (consumed by transferFrom)
        assertEq(usdt.allowance(address(adapter), address(router)), 0);
    }
}

// USDT-like token that reverts on non-zero -> non-zero approvals
contract USDTLikeToken is ERC20Mock {
    function approve(address spender, uint256 amount) public override returns (bool) {
        if (amount != 0 && allowance(msg.sender, spender) != 0) {
            revert("USDT: non-zero to non-zero approval");
        }
        return super.approve(spender, amount);
    }
}
