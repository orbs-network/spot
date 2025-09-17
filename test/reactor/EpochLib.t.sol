// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {EpochLib} from "src/reactor/lib/EpochLib.sol";

contract EpochLibTest is Test {
    mapping(bytes32 => uint256) internal epochs;

    function callEpoch(bytes32 h, uint256 interval) external {
        EpochLib.update(epochs, h, interval);
    }

    function callEpochWithReturn(bytes32 h, uint256 interval) external returns (uint256) {
        return EpochLib.update(epochs, h, interval);
    }

    function setUp() public {
        vm.warp(1 days);
    }

    function test_epoch_zero_allows_once() public {
        bytes32 h = keccak256("h");
        this.callEpoch(h, 0);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h, 0);
    }

    function test_epoch_interval_progression() public {
        bytes32 h = bytes32(uint256(123));
        uint256 interval = 60;
        this.callEpoch(h, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h, interval);
        // Warp to a known next bucket for this base timestamp
        vm.warp(1 days + 59);
        this.callEpoch(h, interval);
    }

    function test_epoch_staggered_by_hash() public {
        uint256 interval = 60;
        bytes32 h1 = bytes32(uint256(1));
        bytes32 h2 = bytes32(uint256(2));
        this.callEpoch(h1, interval);
        this.callEpoch(h2, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h1, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h2, interval);
        // Advance to a bucket where h2 advances first (delta 58s for base divisible by 60)
        vm.warp(1 days + 58);
        this.callEpoch(h2, interval);
        vm.expectRevert(EpochLib.InvalidEpoch.selector);
        this.callEpoch(h1, interval);
        // Then advance to a bucket where h1 advances
        vm.warp(1 days + 59);
        this.callEpoch(h1, interval);
    }

    function test_epoch_returns_current_bucket() public {
        bytes32 h = keccak256("epoch:return");
        uint256 interval = 120;
        uint256 expectedCurrent = (block.timestamp + (uint256(h) % interval)) / interval;
        uint256 current = this.callEpochWithReturn(h, interval);
        assertEq(current, expectedCurrent);
        assertEq(epochs[h], expectedCurrent + 1);
    }
}
