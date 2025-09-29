// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IReactor} from "src/interface/IReactor.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {WMAllowed} from "src/lib/WMAllowed.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SurplusLib} from "src/lib/SurplusLib.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {SettlementLib} from "src/lib/SettlementLib.sol";

/// @title Order executor contract
/// @notice Whitelisted filler contract that runs venue logic and handles surplus distribution
contract Executor is IReactorCallback, WMAllowed {
    error InvalidSender();
    error InvalidOrder();

    address public immutable reactor;

    constructor(address _reactor, address _allowed) WMAllowed(_allowed) {
        reactor = _reactor;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) revert InvalidSender();
        _;
    }

    function execute(CosignedOrder calldata co, Execution calldata x) external onlyAllowed {
        IReactor(reactor).executeWithCallback(co, x);

        SurplusLib.distribute(co.order.exchange.ref, co.order.swapper, co.order.input.token, co.order.exchange.share);
        SurplusLib.distribute(co.order.exchange.ref, co.order.swapper, co.order.output.token, co.order.exchange.share);
    }

    function reactorCallback(bytes32 hash, uint256 resolvedAmountOut, CosignedOrder memory co, Execution memory x)
        external
        override
        onlyReactor
    {
        Address.functionDelegateCall(
            co.order.exchange.adapter,
            abi.encodeWithSelector(IExchangeAdapter.delegateSwap.selector, hash, resolvedAmountOut, co, x)
        );
        SettlementLib.settle(hash, resolvedAmountOut, co, x);
    }

    receive() external payable {}
}
