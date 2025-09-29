// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {RePermit} from "src/repermit/RePermit.sol";

contract DeployRepermit is Script {
    function run() public returns (address repermit) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(RePermit).creationCode);
        console.logBytes32(initCodeHash);

        vm.broadcast();
        repermit = address(new RePermit{salt: salt}());
    }
}
