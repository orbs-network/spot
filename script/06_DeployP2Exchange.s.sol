// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {P2DexAdapter} from "src/adapter/P2DexAdapter.sol";

contract DeployP2Exchange is Script {
    function run() public returns (address exchange) {
        address router = vm.envAddress("ROUTER");
        address permit2 = vm.envAddress("PERMIT2");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(P2DexAdapter).creationCode, abi.encode(router, permit2));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        exchange = address(new P2DexAdapter{salt: salt}(router, permit2));
    }
}
