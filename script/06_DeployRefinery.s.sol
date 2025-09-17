// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {Refinery} from "src/Refinery.sol";

contract DeployRefinery is Script {
    function run() public returns (address refinery) {
        address wm = vm.envAddress("WM");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(Refinery).creationCode, abi.encode(wm));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        refinery = address(new Refinery{salt: salt}(wm));
    }
}
