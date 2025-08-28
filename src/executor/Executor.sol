// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IReactor} from "uniswapx/src/interfaces/IReactor.sol";
import {IReactorCallback} from "uniswapx/src/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "uniswapx/src/interfaces/IValidationCallback.sol";
import {ResolvedOrder, SignedOrder} from "uniswapx/src/base/ReactorStructs.sol";
import {OrderLib} from "src/reactor/OrderLib.sol";
import {Constants} from "src/reactor/Constants.sol";
import {IWM} from "src/interface/IWM.sol";

contract Executor is IReactorCallback, IValidationCallback {
    using SafeERC20 for IERC20;

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

    event Surplus(address indexed ref, address swapper, address token, uint256 amount, uint256 refshare);

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
        _surplus(ref, co.order.info.swapper, address(co.order.input.token), share);
        _surplus(ref, co.order.info.swapper, address(co.order.output.token), share);
    }

    function reactorCallback(ResolvedOrder[] memory orders, bytes memory callbackData) external override onlyReactor {
        ResolvedOrder memory order = orders[0];
        (IMulticall3.Call[] memory calls, uint256 minAmountOutRecipient) =
            abi.decode(callbackData, (IMulticall3.Call[], uint256));

        _executeMulticall(calls);

        if (order.outputs.length != 1) revert InvalidOrder();
        address outToken = address(order.outputs[0].token);
        uint256 outAmount = order.outputs[0].amount;
        address recipient = order.outputs[0].recipient;
        _outputReactor(outToken, outAmount);
        if (minAmountOutRecipient > outAmount) _transfer(outToken, recipient, minAmountOutRecipient - outAmount);

        address ref = abi.decode(order.info.additionalValidationData, (address));

        emit Resolved(
            order.hash, order.info.swapper, ref, address(order.input.token), outToken, order.input.amount, outAmount
        );
    }

    function _executeMulticall(IMulticall3.Call[] memory calls) private {
        Address.functionDelegateCall(multicall, abi.encodeWithSelector(IMulticall3.aggregate.selector, calls));
    }

    function _surplus(address ref, address swapper, address token, uint16 share) private {
        uint256 balance = (token == address(0)) ? address(this).balance : IERC20(token).balanceOf(address(this));
        if (balance == 0) return;

        uint256 refshare = balance * share / Constants.BPS;

        if (refshare > 0) _transfer(token, ref, refshare);
        _transfer(token, swapper, balance - refshare);

        emit Surplus(ref, swapper, token, balance, refshare);
    }

    function _outputReactor(address token, uint256 amount) private {
        if (token == address(0)) {
            _transfer(token, address(reactor), amount);
        } else {
            uint256 allowance = IERC20(token).allowance(address(this), address(reactor));
            IERC20(token).safeApprove(address(reactor), 0);
            IERC20(token).safeApprove(address(reactor), allowance + amount);
        }
    }

    function _transfer(address token, address to, uint256 amount) private {
        if (token == address(0)) Address.sendValue(payable(to), amount);
        else IERC20(token).safeTransfer(to, amount);
    }

    function validate(address filler, ResolvedOrder calldata) external view override {
        if (filler != address(this)) revert InvalidSender();
    }

    receive() external payable {}
}
