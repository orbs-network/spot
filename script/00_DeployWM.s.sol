// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {WM} from "src/ops/WM.sol";
import {UpdateWMWhitelist} from "script/00_UpdateWMWhitelist.s.sol";

contract DeployWM is Script {
    function run() public returns (address wm) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(WM).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("WM already deployed at:", expected);
            wm = expected;
        } else {
            vm.broadcast();
            wm = address(new WM{salt: salt}(owner));
        }

        vm.setEnv("WM", vm.toString(wm));
        new UpdateWMWhitelist().run();
    }
}
