// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {RePermitDexAdapter} from "src/adapter/RePermitDexAdapter.sol";

contract DeployRepermitExchange is Script {
    function run() public returns (address exchange) {
        address repermit = vm.envAddress("REPERMIT");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(RePermitDexAdapter).creationCode, abi.encode(repermit, msg.sender));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("RePermitDexAdapter already deployed at:", expected);
            exchange = expected;
        } else {
            vm.broadcast();
            exchange = address(new RePermitDexAdapter{salt: salt}(repermit, msg.sender));
        }
    }
}
