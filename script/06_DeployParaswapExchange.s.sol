// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {ParaswapDexAdapter} from "src/adapter/ParaswapDexAdapter.sol";

contract DeployParaswapExchange is Script {
    function run() public returns (address exchange) {
        address router = vm.envAddress("ROUTER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(ParaswapDexAdapter).creationCode, abi.encode(router));
        console.logBytes32(initCodeHash);

        vm.broadcast();
        exchange = address(new ParaswapDexAdapter{salt: salt}(router));
    }
}
