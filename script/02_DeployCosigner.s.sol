// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {Cosigner} from "src/ops/Cosigner.sol";

contract DeployCosigner is Script {
    function run() public returns (address cosigner) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(Cosigner).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("Cosigner already deployed at:", expected);
            cosigner = expected;
        } else {
            vm.broadcast();
            cosigner = address(new Cosigner{salt: salt}(owner));
        }

        vm.setEnv("COSIGNER", vm.toString(cosigner));
    }
}
