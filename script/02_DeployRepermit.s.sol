// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {BaseScript} from "script/base/BaseScript.sol";
import {RePermit} from "src/repermit/RePermit.sol";

contract DeployRepermit is BaseScript {
    function run() public returns (address repermit) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(RePermit).creationCode);
        console.logBytes32(initCodeHash);

        vm.broadcast();
        repermit = address(new RePermit{salt: salt}());
    }
}
