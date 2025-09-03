// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {ResolvedOrder, OrderInfo, InputToken, OutputToken} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";

contract SettlementWrapper {
    function settle(ResolvedOrder memory order, SettlementLib.Execution memory execution, address reactor)
        external
        returns (SettlementLib.SettlementResult memory)
    {
        return SettlementLib.settle(order, execution, reactor);
    }
}

contract SettlementLibTest is Test {
    ERC20Mock public tokenIn;
    ERC20Mock public tokenOut;
    USDTMock public usdt;
    address public reactor = makeAddr("reactor");
    address public swapper = makeAddr("swapper");
    address public feeRecipient = makeAddr("feeRecipient");
    
    SettlementWrapper public wrapper;
    
    function setUp() public {
        tokenIn = new ERC20Mock();
        tokenOut = new ERC20Mock();
        usdt = new USDTMock();
        wrapper = new SettlementWrapper();
    }

    function _createResolvedOrder(
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 outAmount,
        address recipient
    ) internal view returns (ResolvedOrder memory) {
        InputToken memory input = InputToken({
            token: inToken,
            amount: inAmount,
            maxAmount: inAmount
        });
        
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({
            token: outToken,
            amount: outAmount,
            recipient: recipient
        });
        
        return ResolvedOrder({
            info: OrderInfo({
                reactor: reactor,
                swapper: swapper,
                nonce: 1,
                deadline: block.timestamp + 1000,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: ""
            }),
            input: input,
            outputs: outputs,
            sig: "",
            hash: keccak256("test")
        });
    }

    function test_settle_basic_functionality() public {
        uint256 outAmount = 100e18;
        uint256 minAmountOut = 95e18;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(0),
                amount: 0,
                recipient: address(0)
            }),
            minAmountOut: minAmountOut,
            data: ""
        });

        // Mint tokens to this contract
        tokenOut.mint(address(this), outAmount);
        
        // Mock the prepareFor functionality by giving tokens to reactor
        tokenOut.mint(reactor, outAmount);

        SettlementLib.SettlementResult memory result = SettlementLib.settle(order, execution, reactor);

        // Check return values
        assertEq(result.orderHash, order.hash);
        assertEq(result.swapper, swapper);
        assertEq(result.inToken, address(tokenIn));
        assertEq(result.outToken, address(tokenOut));
        assertEq(result.inAmount, 200e18);
        assertEq(result.outAmount, outAmount);
    }

    function test_settle_with_min_amount_out_transfer() public {
        uint256 outAmount = 95e18;
        uint256 minAmountOut = 100e18; // Need more than we have
        uint256 shortfall = minAmountOut - outAmount;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(0),
                amount: 0,
                recipient: address(0)
            }),
            minAmountOut: minAmountOut,
            data: ""
        });

        // Mint tokens to this contract to cover the shortfall
        tokenOut.mint(address(this), shortfall + outAmount);
        tokenOut.mint(reactor, outAmount);

        uint256 initialBalance = tokenOut.balanceOf(swapper);

        SettlementLib.settle(order, execution, reactor);

        // Should transfer the shortfall to the recipient
        assertEq(tokenOut.balanceOf(swapper), initialBalance + shortfall);
    }

    function test_settle_with_gas_fee_transfer() public {
        uint256 outAmount = 100e18;
        uint256 feeAmount = 5e18;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(tokenOut),
                amount: feeAmount,
                recipient: feeRecipient
            }),
            minAmountOut: 95e18,
            data: ""
        });

        // Mint tokens to this contract for the fee
        tokenOut.mint(address(this), feeAmount + outAmount);
        tokenOut.mint(reactor, outAmount);

        uint256 initialFeeRecipientBalance = tokenOut.balanceOf(feeRecipient);

        SettlementLib.settle(order, execution, reactor);

        // Should transfer fee to fee recipient
        assertEq(tokenOut.balanceOf(feeRecipient), initialFeeRecipientBalance + feeAmount);
    }

    function test_settle_with_eth_gas_fee() public {
        uint256 outAmount = 100e18;
        uint256 feeAmount = 1 ether;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(0), // ETH
                amount: feeAmount,
                recipient: feeRecipient
            }),
            minAmountOut: 95e18,
            data: ""
        });

        // Give this contract some ETH for the fee
        vm.deal(address(this), feeAmount);
        tokenOut.mint(address(this), outAmount);
        tokenOut.mint(reactor, outAmount);

        uint256 initialFeeRecipientBalance = feeRecipient.balance;

        SettlementLib.settle(order, execution, reactor);

        // Should transfer ETH fee to fee recipient
        assertEq(feeRecipient.balance, initialFeeRecipientBalance + feeAmount);
    }

    function test_settle_with_zero_gas_fee_skips_transfer() public {
        uint256 outAmount = 100e18;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(tokenOut),
                amount: 0, // Zero fee
                recipient: feeRecipient
            }),
            minAmountOut: 95e18,
            data: ""
        });

        tokenOut.mint(address(this), outAmount);
        tokenOut.mint(reactor, outAmount);

        uint256 initialFeeRecipientBalance = tokenOut.balanceOf(feeRecipient);

        SettlementLib.settle(order, execution, reactor);

        // Should not transfer anything when fee is 0
        assertEq(tokenOut.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }

    function test_settle_handles_usdt_like_tokens() public {
        uint256 outAmount = 100e6; // USDT uses 6 decimals
        uint256 feeAmount = 5e6;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(usdt),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(usdt),
                amount: feeAmount,
                recipient: feeRecipient
            }),
            minAmountOut: 95e6,
            data: ""
        });

        // Mint USDT tokens
        usdt.mint(address(this), feeAmount + outAmount);
        usdt.mint(reactor, outAmount);

        uint256 initialFeeRecipientBalance = usdt.balanceOf(feeRecipient);

        SettlementLib.settle(order, execution, reactor);

        // Should handle USDT-like tokens correctly
        assertEq(usdt.balanceOf(feeRecipient), initialFeeRecipientBalance + feeAmount);
    }

    function test_settle_reverts_on_multiple_outputs() public {
        InputToken memory input = InputToken({
            token: address(tokenIn),
            amount: 200e18,
            maxAmount: 200e18
        });
        
        // Create order with multiple outputs
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken({
            token: address(tokenOut),
            amount: 100e18,
            recipient: swapper
        });
        outputs[1] = OutputToken({
            token: address(tokenOut),
            amount: 50e18,
            recipient: swapper
        });
        
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfo({
                reactor: reactor,
                swapper: swapper,
                nonce: 1,
                deadline: block.timestamp + 1000,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: ""
            }),
            input: input,
            outputs: outputs,
            sig: "",
            hash: keccak256("test")
        });

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(0),
                amount: 0,
                recipient: address(0)
            }),
            minAmountOut: 95e18,
            data: ""
        });

        try wrapper.settle(order, execution, reactor) {
            fail("Expected revert for multiple outputs");
        } catch Error(string memory reason) {
            // Expected to revert, but let's check it's the right reason
            assertTrue(bytes(reason).length > 0);
        } catch (bytes memory) {
            // Also acceptable - any revert is fine
            assertTrue(true);
        }
    }

    function test_settle_with_both_shortfall_and_fee() public {
        uint256 outAmount = 95e18;
        uint256 minAmountOut = 100e18;
        uint256 shortfall = minAmountOut - outAmount;
        uint256 feeAmount = 10e18;
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            200e18,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(tokenOut),
                amount: feeAmount,
                recipient: feeRecipient
            }),
            minAmountOut: minAmountOut,
            data: ""
        });

        // Mint enough tokens for both shortfall and fee
        tokenOut.mint(address(this), shortfall + feeAmount + outAmount);
        tokenOut.mint(reactor, outAmount);

        uint256 initialSwapperBalance = tokenOut.balanceOf(swapper);
        uint256 initialFeeRecipientBalance = tokenOut.balanceOf(feeRecipient);

        SettlementLib.settle(order, execution, reactor);

        // Should handle both shortfall and fee transfers
        assertEq(tokenOut.balanceOf(swapper), initialSwapperBalance + shortfall);
        assertEq(tokenOut.balanceOf(feeRecipient), initialFeeRecipientBalance + feeAmount);
    }

    function testFuzz_settle_result_values(
        uint128 inAmount,
        uint128 outAmount,
        uint128 minAmountOut,
        uint128 feeAmount
    ) public {
        vm.assume(inAmount > 0 && outAmount > 0);
        
        ResolvedOrder memory order = _createResolvedOrder(
            address(tokenIn),
            inAmount,
            address(tokenOut),
            outAmount,
            swapper
        );

        SettlementLib.Execution memory execution = SettlementLib.Execution({
            fee: OutputToken({
                token: address(tokenOut),
                amount: feeAmount,
                recipient: feeRecipient
            }),
            minAmountOut: minAmountOut,
            data: ""
        });

        // Mint enough tokens
        uint256 neededTokens = uint256(feeAmount) + outAmount + (minAmountOut > outAmount ? minAmountOut - outAmount : 0);
        tokenOut.mint(address(this), neededTokens);
        tokenOut.mint(reactor, outAmount);

        SettlementLib.SettlementResult memory result = SettlementLib.settle(order, execution, reactor);

        // Verify all result fields are correctly set
        assertEq(result.orderHash, order.hash);
        assertEq(result.swapper, swapper);
        assertEq(result.inToken, address(tokenIn));
        assertEq(result.outToken, address(tokenOut));
        assertEq(result.inAmount, inAmount);
        assertEq(result.outAmount, outAmount);
    }

    // Helper function to receive ETH
    receive() external payable {}
}