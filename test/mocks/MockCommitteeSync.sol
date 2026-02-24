// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ICommitteeSync} from "src/interface/ICommitteeSync.sol";

contract MockCommitteeSync is ICommitteeSync {
    mapping(bytes32 key => mapping(address account => bytes value)) private entries;

    function setConfig(bytes32 key, address account, bytes calldata value) external {
        entries[key][account] = value;
    }

    function clearConfig(bytes32 key, address account) external {
        delete entries[key][account];
    }

    function config(bytes32 key, address account) external view returns (bytes memory value) {
        return entries[key][account];
    }
}
