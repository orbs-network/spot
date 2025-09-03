// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {IReactorCallback} from "src/lib/uniswapx/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {ResolvedOrder, SignedOrder, OutputToken} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IWM} from "src/interface/IWM.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";
import {SurplusLib} from "src/executor/lib/SurplusLib.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";

contract Executor is IReactorCallback, IValidationCallback {
    error InvalidSender();
    error InvalidOrder();

    event Settled(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed exchange,
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount
    );

    address public immutable reactor;
    address public immutable allowed;

    constructor(address _reactor, address _allowed) {
        reactor = _reactor;
        allowed = _allowed;
    }

    modifier onlyAllowed() {
        if (!IWM(allowed).allowed(msg.sender)) revert InvalidSender();
        _;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) revert InvalidSender();
        _;
    }

    struct Execution {
        OutputToken fee;
        uint256 minAmountOut;
        bytes data;
    }

    function execute(OrderLib.CosignedOrder calldata co, Execution calldata x) external onlyAllowed {
        SignedOrder memory so;
        so.order = abi.encode(co);
        so.sig = co.signature;
        IReactor(reactor).executeWithCallback(so, abi.encode(co.order.exchange.adapter, x));

        SurplusLib.distribute(
            co.order.exchange.ref, co.order.info.swapper, co.order.input.token, co.order.exchange.share
        );
        SurplusLib.distribute(
            co.order.exchange.ref, co.order.info.swapper, co.order.output.token, co.order.exchange.share
        );
    }

    function reactorCallback(ResolvedOrder[] memory orders, bytes memory callbackData) external override onlyReactor {
        if (orders.length != 1) revert InvalidOrder();
        (address exchange, Execution memory x) = abi.decode(callbackData, (address, Execution));
        Address.functionDelegateCall(
            exchange, abi.encodeWithSelector(IExchangeAdapter.swap.selector, orders[0], x.data)
        );
        _settle(orders[0], x.minAmountOut, exchange, x.fee);
    }

    function _settle(ResolvedOrder memory order, uint256 minAmountOut, address exchange, OutputToken memory fee)
        private
    {
        if (order.outputs.length != 1) revert InvalidOrder();
        address outToken = address(order.outputs[0].token);
        uint256 outAmount = order.outputs[0].amount;
        address recipient = order.outputs[0].recipient;
        TokenLib.prepareFor(outToken, reactor, outAmount);
        if (minAmountOut > outAmount) {
            TokenLib.transfer(outToken, recipient, minAmountOut - outAmount);
        }

        // Send gas fee to specified recipient if amount > 0
        if (fee.amount > 0) {
            TokenLib.transfer(fee.token, fee.recipient, fee.amount);
        }

        emit Settled(
            order.hash,
            order.info.swapper,
            exchange,
            address(order.input.token),
            outToken,
            order.input.amount,
            outAmount
        );
    }

    function validate(address filler, ResolvedOrder calldata) external view override {
        if (filler != address(this)) revert InvalidSender();
    }

    receive() external payable {}
}
