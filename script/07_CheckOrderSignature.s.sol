// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {OrderReactor} from "src/reactor/OrderReactor.sol";
import {CosignedOrder, Execution} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {IReactorCallback} from "src/interface/IReactorCallback.sol";
import {RePermit} from "src/repermit/RePermit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckOrderSignature is Script {
    using stdJson for string;

    function run() external returns (bytes32 orderHash, bytes32 repermitDigest) {
        vm.createSelectFork(vm.envString("RPC_URL"));

        string[] memory cmd = new string[](5);
        cmd[0] = "jq";
        cmd[1] = "-S";
        cmd[2] = "-c";
        cmd[3] = ".";
        cmd[4] = "script/input/order.json";
        string memory json = string(vm.ffi(cmd));

        CosignedOrder memory co = abi.decode(json.parseRaw(".cosigned"), (CosignedOrder));
        Execution memory execParams = abi.decode(json.parseRaw(".execution"), (Execution));

        _mockToken(co.order.input.token);
        _mockToken(co.order.output.token);
        vm.mockCall(co.order.executor, IReactorCallback.reactorCallback.selector, "");

        OrderReactor reactor = OrderReactor(payable(co.order.reactor));
        orderHash = OrderLib.hash(co.order);

        vm.prank(co.order.executor);
        reactor.executeWithCallback(co, execParams);

        repermitDigest = RePermit(reactor.repermit()).hashTypedData(orderHash);

        console.log("Order hash");
        console.logBytes32(orderHash);
        console.log("RePermit hash");
        console.logBytes32(repermitDigest);
        console.log("Matches?");
        console.log(orderHash == repermitDigest);
    }

    function _mockToken(address token) private {
        if (token == address(0)) return;
        vm.mockCall(token, IERC20.transferFrom.selector, abi.encode(true));
        vm.mockCall(token, IERC20.transfer.selector, abi.encode(true));
        vm.mockCall(token, IERC20.approve.selector, abi.encode(true));
        vm.mockCall(token, IERC20.allowance.selector, abi.encode(type(uint256).max));
        vm.mockCall(token, IERC20.balanceOf.selector, abi.encode(type(uint256).max));
    }
}
