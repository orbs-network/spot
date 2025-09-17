// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {OrderReactor} from "src/reactor/OrderReactor.sol";

contract DeployReactor is Script {
    function run() public returns (address reactor) {
        address repermit = vm.envAddress("REPERMIT");
        address cosigner = vm.envAddress("COSIGNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(OrderReactor).creationCode, abi.encode(repermit, cosigner));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        reactor = address(new OrderReactor{salt: salt}(repermit, cosigner));
    }
}
