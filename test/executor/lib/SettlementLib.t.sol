// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IValidationCallback} from "src/interface/IValidationCallback.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract SettlementWrapper {
    function settle(
        OrderLib.CosignedOrder memory cosignedOrder,
        SettlementLib.Execution memory execution,
        address reactor,
        address exchange
    ) external {
        SettlementLib.settle(cosignedOrder, execution, reactor, exchange, OrderLib.hash(cosignedOrder.order));
    }
}

contract SettlementLibTest is Test {
    ERC20Mock public tokenIn;
    ERC20Mock public tokenOut;
    USDTMock public usdt;
    address public reactor = makeAddr("reactor");
    address public swapper = makeAddr("swapper");
    address public feeRecipient = makeAddr("feeRecipient");
    address public exchange = makeAddr("exchange");

    SettlementWrapper public wrapper;

    // Duplicate event signature for expectEmit matching
    event Settled(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed exchange,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    );

    function setUp() public {
        tokenIn = new ERC20Mock();
        tokenOut = new ERC20Mock();
        usdt = new USDTMock();
        wrapper = new SettlementWrapper();
    }

    function _createCosignedOrder(
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount,
        address recipient
    ) internal view returns (OrderLib.CosignedOrder memory) {
        OrderLib.CosignedOrder memory cosignedOrder;
        cosignedOrder.order.info = OrderLib.OrderInfo({
            reactor: reactor,
            swapper: swapper,
            nonce: 1,
            deadline: block.timestamp + 1000,
            additionalValidationContract: address(0),
            additionalValidationData: ""
        });
        cosignedOrder.order.input = OrderLib.Input({
            token: inToken,
            amount: inAmount,
            maxAmount: inAmount
        });
        cosignedOrder.order.output = OrderLib.Output({
            token: outToken,
            amount: outAmount,
            maxAmount: type(uint256).max,
            recipient: recipient
        });
        cosignedOrder.signature = "";
        cosignedOrder.cosignature = "";
        
        return cosignedOrder;
    }

    function _createExecution(address feeToken, uint256 feeAmount, address recipient, uint256 minAmountOut)
        internal
        pure
        returns (SettlementLib.Execution memory)
    {
        return SettlementLib.Execution({
            fee: OrderLib.Output({token: feeToken, amount: feeAmount, recipient: recipient, maxAmount: type(uint256).max}),
            minAmountOut: minAmountOut,
            data: ""
        });
    }

    function _mintTokensForSettlement(address token, uint256 wrapperAmount, uint256 reactorAmount) internal {
        ERC20Mock(token).mint(address(wrapper), wrapperAmount);
        ERC20Mock(token).mint(reactor, reactorAmount);
    }

    function _expectSettledEvent(OrderLib.CosignedOrder memory cosignedOrder, uint256 inAmount, uint256 outAmount) internal {
        vm.expectEmit(address(wrapper));
        emit Settled(OrderLib.hash(cosignedOrder.order), swapper, exchange, cosignedOrder.order.input.token, cosignedOrder.order.output.token, inAmount, outAmount);
    }

    function test_settle_basic_functionality() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 minAmountOut = 95 ether;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution = _createExecution(address(0), 0, address(0), minAmountOut);

        _mintTokensForSettlement(address(tokenOut), outAmount, outAmount);

        _expectSettledEvent(order, inAmount, outAmount);
        wrapper.settle(order, execution, reactor, exchange);
    }

    function test_settle_with_min_amount_out_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 95 ether;
        uint256 minAmountOut = 100 ether;
        uint256 shortfall = minAmountOut - outAmount;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution = _createExecution(address(0), 0, address(0), minAmountOut);

        _mintTokensForSettlement(address(tokenOut), shortfall + outAmount, outAmount);

        uint256 initialBalance = tokenOut.balanceOf(swapper);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(tokenOut.balanceOf(swapper), initialBalance + shortfall);
    }

    function test_settle_with_gas_fee_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 feeAmount = 5 ether;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution =
            _createExecution(address(tokenOut), feeAmount, feeRecipient, 95 ether);

        _mintTokensForSettlement(address(tokenOut), feeAmount + outAmount, outAmount);

        uint256 initialBalance = tokenOut.balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(tokenOut.balanceOf(feeRecipient), initialBalance + feeAmount);
    }

    function test_settle_with_eth_gas_fee() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;
        uint256 feeAmount = 1 ether;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution = _createExecution(address(0), feeAmount, feeRecipient, 95 ether);

        vm.deal(address(wrapper), feeAmount);
        _mintTokensForSettlement(address(tokenOut), outAmount, outAmount);

        uint256 initialBalance = feeRecipient.balance;
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(feeRecipient.balance, initialBalance + feeAmount);
    }

    function test_settle_with_zero_gas_fee_skips_transfer() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100 ether;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution = _createExecution(address(tokenOut), 0, feeRecipient, 95 ether);

        _mintTokensForSettlement(address(tokenOut), outAmount, outAmount);

        uint256 initialBalance = tokenOut.balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(tokenOut.balanceOf(feeRecipient), initialBalance);
    }

    function test_settle_handles_usdt_like_tokens() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 100e6;
        uint256 feeAmount = 5e6;

        OrderLib.CosignedOrder memory order = _createCosignedOrder(address(tokenIn), inAmount, address(usdt), outAmount, swapper);

        SettlementLib.Execution memory execution = _createExecution(address(usdt), feeAmount, feeRecipient, 95e6);

        usdt.mint(address(wrapper), feeAmount + outAmount);
        usdt.mint(reactor, outAmount);

        uint256 initialBalance = usdt.balanceOf(feeRecipient);
        wrapper.settle(order, execution, reactor, exchange);

        assertEq(usdt.balanceOf(feeRecipient), initialBalance + feeAmount);
    }

    function test_settle_with_both_shortfall_and_fee() public {
        uint256 inAmount = 200 ether;
        uint256 outAmount = 95 ether;
        uint256 minAmountOut = 100 ether;
        uint256 shortfall = minAmountOut - outAmount;
        uint256 feeAmount = 10 ether;

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution =
            _createExecution(address(tokenOut), feeAmount, feeRecipient, minAmountOut);

        _mintTokensForSettlement(address(tokenOut), shortfall + feeAmount + outAmount, outAmount);

        uint256 initialSwapperBalance = tokenOut.balanceOf(swapper);
        uint256 initialFeeBalance = tokenOut.balanceOf(feeRecipient);

        wrapper.settle(order, execution, reactor, exchange);

        assertEq(tokenOut.balanceOf(swapper), initialSwapperBalance + shortfall);
        assertEq(tokenOut.balanceOf(feeRecipient), initialFeeBalance + feeAmount);
    }

    function testFuzz_settle_result_values(uint128 inAmount, uint128 outAmount, uint128 minAmountOut, uint128 feeAmount)
        public
    {
        vm.assume(inAmount > 0 && outAmount > 0);

        OrderLib.CosignedOrder memory order =
            _createCosignedOrder(address(tokenIn), inAmount, address(tokenOut), outAmount, swapper);

        SettlementLib.Execution memory execution =
            _createExecution(address(tokenOut), feeAmount, feeRecipient, minAmountOut);

        uint256 neededTokens =
            uint256(feeAmount) + outAmount + (minAmountOut > outAmount ? minAmountOut - outAmount : 0);
        _mintTokensForSettlement(address(tokenOut), neededTokens, outAmount);

        _expectSettledEvent(order, inAmount, outAmount);
        wrapper.settle(order, execution, reactor, exchange);
    }

    // Helper function to receive ETH
    receive() external payable {}
}
