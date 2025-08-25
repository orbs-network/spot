// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {EpochLib} from "src/reactor/EpochLib.sol";

contract EpochLibTest is Test {
    mapping(bytes32 => uint256) internal epochs;

    function callEpoch(bytes32 h, uint256 interval) external {
        EpochLib.update(epochs, h, interval);
    }

    function test_epoch_zero_allows_once() public {
        bytes32 h = keccak256("h");
        this.callEpoch(h, 0);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h, 0);
    }

    function test_epoch_interval_progression() public {
        bytes32 h = keccak256("h");
        uint256 interval = 60;
        // First call succeeds
        this.callEpoch(h, interval);
        // Second call in same bucket reverts
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h, interval);
        // Warp to next bucket boundary based on hash-derived offset
        uint256 offset = uint256(h) % interval;
        uint256 rem = (block.timestamp + offset) % interval;
        uint256 delta = rem == 0 ? interval : (interval - rem);
        vm.warp(block.timestamp + delta);
        // Now next epoch should be allowed
        this.callEpoch(h, interval);
    }

    function test_epoch_staggered_by_hash() public {
        uint256 interval = 60;
        bytes32 h1 = bytes32(uint256(1));
        bytes32 h2 = bytes32(uint256(2));
        // Align timestamp so advancing to h1's next boundary does not
        // also advance h2. Ensure (block.timestamp + o1) % interval == interval - 1
        uint256 o1 = uint256(h1) % interval;
        uint256 align = (interval - 1 + interval - ((block.timestamp + o1) % interval)) % interval;
        if (align != 0) vm.warp(block.timestamp + align);
        // Initial calls succeed for both
        this.callEpoch(h1, interval);
        this.callEpoch(h2, interval);
        // Repeating in same bucket reverts
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h1, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h2, interval);

        // Advance to h1's next bucket boundary only
        uint256 rem1 = (block.timestamp + o1) % interval;
        uint256 d1 = rem1 == 0 ? interval : (interval - rem1);
        vm.warp(block.timestamp + d1);

        // h1 should now allow; h2 should still be locked (different offset)
        this.callEpoch(h1, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h2, interval);

        // Advance to h2's next boundary and allow
        uint256 o2 = uint256(h2) % interval;
        uint256 rem2 = (block.timestamp + o2) % interval;
        uint256 d2 = rem2 == 0 ? interval : (interval - rem2);
        vm.warp(block.timestamp + d2);
        this.callEpoch(h2, interval);
    }
}
