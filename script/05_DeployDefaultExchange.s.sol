// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {BaseScript} from "script/base/BaseScript.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";

contract DeployDefaultExchange is BaseScript {
    function run() public returns (address exchange) {
        address router = vm.envAddress("ROUTER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(DefaultDexAdapter).creationCode, abi.encode(router));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        exchange = address(new DefaultDexAdapter{salt: salt}(router));
    }
}
