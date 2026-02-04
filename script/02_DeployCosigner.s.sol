// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {Cosigner} from "src/ops/Cosigner.sol";

contract DeployCosigner is Script {
    address private constant DEFAULT_SIGNER = 0x61C4c6670FBA2Fa8Eb5eb2d930ae6d05fC78f05C;

    function run() public returns (address cosigner) {
        address owner = vm.envAddress("OWNER");
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        bytes32 initCodeHash = hashInitCode(type(Cosigner).creationCode, abi.encode(owner));
        console.logBytes32(initCodeHash);

        address expected = vm.computeCreate2Address(salt, initCodeHash);
        if (expected.code.length > 0) {
            console.log("Cosigner already deployed at:", expected);
            cosigner = expected;
        } else {
            vm.broadcast();
            cosigner = address(new Cosigner{salt: salt}(owner));
            vm.broadcast();
            Cosigner(cosigner).approve(DEFAULT_SIGNER, type(uint256).max);
        }

        vm.setEnv("COSIGNER", vm.toString(cosigner));
    }
}
