// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {DelegatingAdapter} from "src/adapter/DelegatingAdapter.sol";

contract DeployDelegatingAdapter is Script {
    function run() public returns (address adapter) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(DelegatingAdapter).creationCode);
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("DelegatingAdapter already deployed at:", expected);
            adapter = expected;
        } else {
            vm.broadcast();
            adapter = address(new DelegatingAdapter{salt: salt}());
        }
    }
}
