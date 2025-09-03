// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {Executor} from "src/executor/Executor.sol";
import {BaseTest} from "test/base/BaseTest.sol";
import {
    ResolvedOrder, SignedOrder, OrderInfo, InputToken, OutputToken
} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";

// Simple Uniswap V2-style router for integration testing
contract SimpleRouter {
    mapping(address => mapping(address => uint256)) public exchangeRates; // inputToken -> outputToken -> rate

    function setExchangeRate(address inputToken, address outputToken, uint256 rate) external {
        exchangeRates[inputToken][outputToken] = rate;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "SimpleRouter: invalid path");

        address tokenIn = path[0];
        address tokenOut = path[1];

        // Transfer input tokens from caller
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Calculate output amount based on exchange rate
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        require(rate > 0, "SimpleRouter: no rate set");

        uint256 amountOut = (amountIn * rate) / 1e18;
        require(amountOut >= amountOutMin, "SimpleRouter: insufficient output amount");

        // Mint output tokens to recipient (simulate swap)
        ERC20Mock(tokenOut).mint(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 /* deadline */ )
        external
        payable
        returns (uint256[] memory amounts)
    {
        require(path.length == 1, "SimpleRouter: invalid path");

        address tokenOut = path[0];

        // Calculate output amount based on exchange rate (ETH = address(0))
        uint256 rate = exchangeRates[address(0)][tokenOut];
        require(rate > 0, "SimpleRouter: no rate set");

        uint256 amountOut = (msg.value * rate) / 1e18;
        require(amountOut >= amountOutMin, "SimpleRouter: insufficient output amount");

        // Mint output tokens to recipient (simulate swap)
        ERC20Mock(tokenOut).mint(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOut;
    }
}

contract DefaultDexAdapterIntegrationTest is BaseTest {
    Executor public exec;
    MockReactor public reactor;
    DefaultDexAdapter public adapter;
    SimpleRouter public router;
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    address public swapper = makeAddr("swapper");
    address public recipient = makeAddr("recipient");

    function setUp() public override {
        super.setUp();
        vm.warp(1_000_000);

        reactor = new MockReactor();
        exec = new Executor(address(reactor), wm);
        adapter = new DefaultDexAdapter();
        router = new SimpleRouter();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        // Set exchange rates: 1 tokenA = 2 tokenB, 1 ETH = 1000 tokenB
        router.setExchangeRate(address(tokenA), address(tokenB), 2e18); // 2 tokenB per 1 tokenA
        router.setExchangeRate(address(0), address(tokenB), 1000e18); // 1000 tokenB per 1 ETH

        // Fund executor with input tokens
        tokenA.mint(address(exec), 10000e18);
        vm.deal(address(exec), 10 ether);

        allowThis();
    }

    function test_integration_ERC20_swap_via_executor() public {
        // Create a resolved order
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0] = ResolvedOrder({
            info: OrderInfo({
                reactor: address(reactor),
                swapper: swapper,
                nonce: 1,
                deadline: block.timestamp + 1000,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: ""
            }),
            input: InputToken({token: address(tokenA), amount: 1000e18, maxAmount: 1000e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: bytes32(0)
        });

        orders[0].outputs[0] = OutputToken({
            token: address(tokenB),
            amount: 1800e18, // expect at least 1800 tokenB (allowing for some slippage)
            recipient: recipient
        });

        // Prepare swap parameters for the adapter
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes memory swapCall = abi.encodeWithSelector(
            SimpleRouter.swapExactTokensForTokens.selector,
            1000e18, // amountIn
            1800e18, // amountOutMin
            path,
            recipient,
            block.timestamp + 1000
        );

        DefaultDexAdapter.SwapParams memory swapParams =
            DefaultDexAdapter.SwapParams({router: address(router), callData: swapCall});

        Executor.Execution memory execution = Executor.Execution({minAmountOut: 1800e18, data: abi.encode(swapParams)});

        bytes memory callbackData = abi.encode(address(adapter), execution);

        // Check initial balances
        uint256 initialTokenA = tokenA.balanceOf(address(exec));
        uint256 initialTokenB = tokenB.balanceOf(recipient);

        // Execute the callback (simulating what would happen in a real execution)
        vm.prank(address(reactor));
        exec.reactorCallback(orders, callbackData);

        // Verify the swap occurred
        assertEq(tokenA.balanceOf(address(exec)), initialTokenA - 1000e18, "Input tokens should be spent");
        assertEq(tokenB.balanceOf(recipient), initialTokenB + 2000e18, "Output tokens should be received");

        // Verify approval was set for the reactor to handle the output
        assertEq(
            tokenB.allowance(address(exec), address(reactor)),
            1800e18,
            "Reactor should be approved for order output amount"
        );
    }

    function test_integration_ETH_swap_via_executor() public {
        // Create a resolved order for ETH -> Token
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0] = ResolvedOrder({
            info: OrderInfo({
                reactor: address(reactor),
                swapper: swapper,
                nonce: 1,
                deadline: block.timestamp + 1000,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: ""
            }),
            input: InputToken({
                token: address(0), // ETH
                amount: 1 ether,
                maxAmount: 1 ether
            }),
            outputs: new OutputToken[](1),
            sig: "",
            hash: bytes32(0)
        });

        orders[0].outputs[0] = OutputToken({
            token: address(tokenB),
            amount: 900e18, // expect at least 900 tokenB
            recipient: recipient
        });

        // Prepare ETH swap parameters
        address[] memory path = new address[](1);
        path[0] = address(tokenB);

        bytes memory swapCall = abi.encodeWithSelector(
            SimpleRouter.swapExactETHForTokens.selector,
            900e18, // amountOutMin
            path,
            recipient,
            block.timestamp + 1000
        );

        DefaultDexAdapter.SwapParams memory swapParams =
            DefaultDexAdapter.SwapParams({router: address(router), callData: swapCall});

        Executor.Execution memory execution = Executor.Execution({minAmountOut: 900e18, data: abi.encode(swapParams)});

        bytes memory callbackData = abi.encode(address(adapter), execution);

        // Check initial balances
        uint256 initialETH = address(exec).balance;
        uint256 initialTokenB = tokenB.balanceOf(recipient);

        // Execute the callback
        vm.prank(address(reactor));
        exec.reactorCallback(orders, callbackData);

        // Verify the swap occurred
        assertEq(address(exec).balance, initialETH - 1 ether, "ETH should be spent");
        assertEq(tokenB.balanceOf(recipient), initialTokenB + 1000e18, "Output tokens should be received");
    }

    function test_integration_adapter_resets_approval() public {
        // Test that approvals are reset to 0 after swap for security
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0] = ResolvedOrder({
            info: OrderInfo({
                reactor: address(reactor),
                swapper: swapper,
                nonce: 1,
                deadline: block.timestamp + 1000,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: ""
            }),
            input: InputToken({token: address(tokenA), amount: 100e18, maxAmount: 100e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: bytes32(0)
        });

        orders[0].outputs[0] = OutputToken({token: address(tokenB), amount: 180e18, recipient: recipient});

        // Pre-set a non-zero allowance to verify it gets reset
        vm.prank(address(exec));
        tokenA.approve(address(router), 999);
        assertEq(tokenA.allowance(address(exec), address(router)), 999, "Pre-condition: non-zero allowance");

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes memory swapCall = abi.encodeWithSelector(
            SimpleRouter.swapExactTokensForTokens.selector, 100e18, 180e18, path, recipient, block.timestamp + 1000
        );

        DefaultDexAdapter.SwapParams memory swapParams =
            DefaultDexAdapter.SwapParams({router: address(router), callData: swapCall});

        Executor.Execution memory execution = Executor.Execution({minAmountOut: 180e18, data: abi.encode(swapParams)});

        bytes memory callbackData = abi.encode(address(adapter), execution);

        vm.prank(address(reactor));
        exec.reactorCallback(orders, callbackData);

        // Verify approval was reset to 0
        assertEq(tokenA.allowance(address(exec), address(router)), 0, "Approval should be reset to 0");
    }
}
