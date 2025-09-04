// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {IValidationCallback} from "src/interface/IValidationCallback.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IWM} from "src/interface/IWM.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SurplusLib} from "src/executor/lib/SurplusLib.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";

contract Executor is IReactorCallback, IValidationCallback {
    error InvalidSender();
    error InvalidOrder();

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

    function execute(OrderLib.CosignedOrder calldata co, SettlementLib.Execution calldata x) external onlyAllowed {
        IReactor(reactor).executeWithCallback(co, abi.encode(co.order.exchange.adapter, x));

        SurplusLib.distribute(
            co.order.exchange.ref, co.order.info.swapper, co.order.input.token, co.order.exchange.share
        );
        SurplusLib.distribute(
            co.order.exchange.ref, co.order.info.swapper, co.order.output.token, co.order.exchange.share
        );
    }

    function reactorCallback(OrderLib.CosignedOrder memory cosignedOrder, bytes32 orderHash, bytes memory callbackData) external override onlyReactor {
        (address exchange, SettlementLib.Execution memory x) =
            abi.decode(callbackData, (address, SettlementLib.Execution));
        Address.functionDelegateCall(
            exchange, abi.encodeWithSelector(IExchangeAdapter.swap.selector, cosignedOrder, x.data)
        );
        SettlementLib.settle(cosignedOrder, x, reactor, exchange, orderHash);
    }

    function validate(address filler, OrderLib.CosignedOrder calldata) external view override {
        if (filler != address(this)) revert InvalidSender();
    }

    receive() external payable {}
}
