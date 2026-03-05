// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";

contract DeployUniversalAdapter is Script {
    function run() public returns (address adapter) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(UniversalAdapter).creationCode);
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("UniversalAdapter already deployed at:", expected);
            adapter = expected;
        } else {
            vm.broadcast();
            adapter = address(new UniversalAdapter{salt: salt}());
        }
    }
}
