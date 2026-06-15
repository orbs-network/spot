// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {DynamicP2DexAdapter} from "src/adapter/DynamicP2DexAdapter.sol";

contract DeployDynamicP2Adapter is Script {
    function run() public returns (address adapter) {
        address permit2 = vm.envAddress("PERMIT2");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(DynamicP2DexAdapter).creationCode, abi.encode(permit2));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("DynamicP2DexAdapter already deployed at:", expected);
            adapter = expected;
        } else {
            vm.broadcast();
            adapter = address(new DynamicP2DexAdapter{salt: salt}(permit2));
        }
    }
}
