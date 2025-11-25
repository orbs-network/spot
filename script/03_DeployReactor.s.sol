// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {OrderReactor} from "src/OrderReactor.sol";

contract DeployReactor is Script {
    function run() public returns (address reactor) {
        address repermit = vm.envAddress("REPERMIT");
        address cosigner = vm.envAddress("COSIGNER");
        address wm = vm.envAddress("WM");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(OrderReactor).creationCode, abi.encode(repermit, cosigner, wm));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("OrderReactor already deployed at:", expected);
            reactor = expected;
        } else {
            vm.broadcast();
            reactor = address(new OrderReactor{salt: salt}(repermit, cosigner, wm));
        }

        vm.setEnv("REACTOR", vm.toString(reactor));
    }
}
