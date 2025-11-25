// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {RePermit} from "src/RePermit.sol";

contract DeployRepermit is Script {
    function run() public returns (address repermit) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(RePermit).creationCode);
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("RePermit already deployed at:", expected);
            repermit = expected;
        } else {
            vm.broadcast();
            repermit = address(new RePermit{salt: salt}());
        }

        vm.setEnv("REPERMIT", vm.toString(repermit));
    }
}
