// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {Executor} from "src/Executor.sol";

contract DeployExecutor is Script {
    function run() public returns (address executor) {
        address reactor = vm.envAddress("REACTOR");
        address wm = vm.envAddress("WM");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(Executor).creationCode, abi.encode(reactor, wm));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("Executor already deployed at:", expected);
            executor = expected;
        } else {
            vm.broadcast();
            executor = address(new Executor{salt: salt}(reactor, wm));
        }

        vm.setEnv("EXECUTOR", vm.toString(executor));
    }
}
