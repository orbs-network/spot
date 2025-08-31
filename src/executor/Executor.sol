// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {IReactor} from "src/lib/uniswapx/interfaces/IReactor.sol";
import {IReactorCallback} from "src/lib/uniswapx/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "src/lib/uniswapx/interfaces/IValidationCallback.sol";
import {ResolvedOrder, SignedOrder} from "src/lib/uniswapx/base/ReactorStructs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {IWM} from "src/interface/IWM.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TokenLib} from "src/executor/lib/TokenLib.sol";
import {SurplusLib} from "src/executor/lib/SurplusLib.sol";

contract Executor is IReactorCallback, IValidationCallback {
    error InvalidSender();
    error InvalidOrder();

    event Resolved(
        bytes32 indexed orderHash,
        address indexed swapper,
        address indexed ref,
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount
    );

    address public immutable multicall;
    address public immutable reactor;
    address public immutable allowed;

    constructor(address _multicall, address _reactor, address _allowed) {
        multicall = _multicall;
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

    function execute(SignedOrder calldata order, IMulticall3.Call[] calldata calls, uint256 minAmountOutRecipient)
        external
        onlyAllowed
    {
        IReactor(reactor).executeWithCallback(order, abi.encode(calls, minAmountOutRecipient));

        OrderLib.CosignedOrder memory co = abi.decode(order.order, (OrderLib.CosignedOrder));
        (address ref, uint16 share) = abi.decode(co.order.info.additionalValidationData, (address, uint16));
        SurplusLib.distribute(ref, co.order.info.swapper, address(co.order.input.token), share);
        SurplusLib.distribute(ref, co.order.info.swapper, address(co.order.output.token), share);
    }

    function reactorCallback(ResolvedOrder[] memory orders, bytes memory callbackData) external override onlyReactor {
        ResolvedOrder memory order = orders[0];
        (IMulticall3.Call[] memory calls, uint256 minAmountOutRecipient) =
            abi.decode(callbackData, (IMulticall3.Call[], uint256));

        Address.functionDelegateCall(multicall, abi.encodeWithSelector(IMulticall3.aggregate.selector, calls));

        if (order.outputs.length != 1) revert InvalidOrder();
        address outToken = address(order.outputs[0].token);
        uint256 outAmount = order.outputs[0].amount;
        address recipient = order.outputs[0].recipient;
        TokenLib.prepareFor(outToken, reactor, outAmount);
        if (minAmountOutRecipient > outAmount) {
            TokenLib.transfer(outToken, recipient, minAmountOutRecipient - outAmount);
        }

        address ref = abi.decode(order.info.additionalValidationData, (address));

        emit Resolved(
            order.hash, order.info.swapper, ref, address(order.input.token), outToken, order.input.amount, outAmount
        );
    }

    function validate(address filler, ResolvedOrder calldata) external view override {
        if (filler != address(this)) revert InvalidSender();
    }

    receive() external payable {}
}
