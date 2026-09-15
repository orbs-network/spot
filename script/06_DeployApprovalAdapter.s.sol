// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {ApprovalDexAdapter} from "src/adapter/ApprovalDexAdapter.sol";

contract DeployApprovalAdapter is Script {
    function run() public returns (address adapter) {
        address router = vm.envAddress("ROUTER");
        address spender = vm.envAddress("SPENDER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));
        bytes32 initCodeHash = hashInitCode(type(ApprovalDexAdapter).creationCode, abi.encode(router, spender));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("ApprovalDexAdapter already deployed at:", expected);
            adapter = expected;
        } else {
            vm.broadcast();
            adapter = address(new ApprovalDexAdapter{salt: salt}(router, spender));
        }
    }
}
