// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {BaseScript} from "script/base/BaseScript.sol";

import {WM} from "src/WM.sol";

contract DeployWM is BaseScript {
    function run() public returns (address wmAddr) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(WM).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        wmAddr = address(new WM{salt: salt}(owner));
    }
}
