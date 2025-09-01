// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IReactor} from "uniswapx/src/interfaces/IReactor.sol";
import {IReactorCallback} from "uniswapx/src/interfaces/IReactorCallback.sol";
import {IValidationCallback} from "uniswapx/src/interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo, InputToken, OutputToken, SignedOrder} from "uniswapx/src/base/ReactorStructs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockReactor is IReactor {
    // Tracking fields used by unit tests
    SignedOrder public lastOrder;
    bytes public lastCallbackData;
    address public lastSender;

    function execute(SignedOrder calldata) external payable {}

    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData) external payable {
        // record for tests
        lastSender = msg.sender;
        lastOrder = order;
        lastCallbackData = callbackData;

        ResolvedOrder[] memory ros = new ResolvedOrder[](1);

        OrderLib.CosignedOrder memory co = abi.decode(order.order, (OrderLib.CosignedOrder));
        OutputToken[] memory outs = new OutputToken[](1);
        outs[0] = OutputToken({token: address(co.order.output.token), amount: 500, recipient: co.order.info.swapper});

        address adapter = co.order.exchange.adapter;

        ros[0] = ResolvedOrder({
            info: OrderInfo({
                reactor: IReactor(address(this)),
                swapper: co.order.info.swapper,
                nonce: 1,
                deadline: 1_086_400,
                additionalValidationContract: IValidationCallback(address(0)),
                additionalValidationData: abi.encode(adapter)
            }),
            input: InputToken({token: ERC20(address(co.order.input.token)), amount: 100, maxAmount: 100}),
            outputs: outs,
            sig: bytes(""),
            hash: bytes32(uint256(123))
        });

        IReactorCallback(msg.sender).reactorCallback(ros, callbackData);
    }

    function executeBatch(SignedOrder[] calldata) external payable {}

    function executeBatchWithCallback(SignedOrder[] calldata, bytes calldata) external payable {}

    receive() external payable {}
}
