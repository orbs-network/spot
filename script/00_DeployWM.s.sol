// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {WM} from "src/ops/WM.sol";
import {UpdateWMWhitelist} from "script/01_UpdateWMWhitelist.s.sol";

contract DeployWM is Script {
    function run() public returns (address wmAddr) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(WM).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        try new WM{salt: salt}(owner) returns (WM deployed) {
            wmAddr = address(deployed);
        } catch (bytes memory err) {
            console.log("wm deployment skipped");
            console.logBytes(err);
            wmAddr = vm.envOr("WM", address(0));
        }

        new UpdateWMWhitelist().run();
    }
}
