// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {BaseScript} from "script/base/BaseScript.sol";

import {WM} from "src/WM.sol";

contract UpdateWMWhitelist is BaseScript {
    uint256 public constant BATCH_SIZE = 300;
    uint256 public constant MAX_WHITELIST_SIZE = 200;
    string internal constant WM_LIST_FILE = "wm.json";
    string internal constant WM_EXTRA_LIST_FILE = "wm2.json";

    function run() public {
        WM admin = WM(payable(vm.envAddress("WM")));

        if (address(admin).code.length == 0) {
            console.log("wm not deployed");
            return;
        }

        string memory root = string.concat(vm.projectRoot(), "/script/input/");

        address[] memory mainList =
            abi.decode(vm.parseJson(vm.readFile(string.concat(root, WM_LIST_FILE))), (address[]));

        uint256 limit = mainList.length < MAX_WHITELIST_SIZE ? mainList.length : MAX_WHITELIST_SIZE;

        require(limit > 0, "whitelist empty");

        address[] memory incrementalList =
            abi.decode(vm.parseJson(vm.readFile(string.concat(root, WM_EXTRA_LIST_FILE))), (address[]));

        uint256 combinedLength = limit + incrementalList.length;

        address[] memory list = new address[](combinedLength);

        for (uint256 i = 0; i < limit; i++) {
            list[i] = mainList[i];
        }

        for (uint256 i = 0; i < incrementalList.length; i++) {
            list[limit + i] = incrementalList[i];
        }

        if (admin.allowed(list[0]) && admin.allowed(list[list.length - 1])) {
            console.log("wm whitelist already updated");
            return;
        }

        for (uint256 i = 0; i < list.length; i += BATCH_SIZE) {
            uint256 size = i + BATCH_SIZE < list.length ? BATCH_SIZE : list.length - i;

            address[] memory batch = new address[](size);
            for (uint256 j = 0; j < size; j++) {
                batch[j] = list[i + j];
            }

            vm.broadcast();
            admin.set(batch, true);

            console.log("whitelist updated, batch", i);
        }

        require(admin.allowed(admin.owner()), "owner not allowed?");
        require(admin.allowed(list[0]), "first not allowed?");
        require(admin.allowed(list[list.length - 1]), "last not allowed?");
    }
}
