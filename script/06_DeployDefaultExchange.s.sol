// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";

contract DeployDefaultExchange is Script {
    function run() public returns (address exchange) {
        address router = vm.envAddress("ROUTER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(DefaultDexAdapter).creationCode, abi.encode(router));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("DefaultDexAdapter already deployed at:", expected);
            exchange = expected;
        } else {
            vm.broadcast();
            exchange = address(new DefaultDexAdapter{salt: salt}(router));
        }
    }
}
