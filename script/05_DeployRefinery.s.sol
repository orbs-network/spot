// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {Refinery} from "src/ops/Refinery.sol";

contract DeployRefinery is Script {
    function run() public returns (address refinery) {
        address wm = vm.envAddress("WM");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(Refinery).creationCode, abi.encode(wm));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        refinery = address(new Refinery{salt: salt}(wm));

        vm.setEnv("REFINERY", vm.toString(refinery));
    }
}
