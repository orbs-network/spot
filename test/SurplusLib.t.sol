// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {SurplusLib} from "src/lib/SurplusLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract SurplusHarness {
    function distribute(address ref, address swapper, address token, uint32 shareBps) external {
        SurplusLib.distribute(ref, swapper, token, shareBps);
    }
}

contract SurplusLibTest is Test {
    SurplusHarness internal harness;
    ERC20Mock internal token;
    address internal swapper;
    address internal ref;

    event Surplus(address indexed ref, address swapper, address token, uint256 amount, uint256 refshare);

    function setUp() public {
        harness = new SurplusHarness();
        token = new ERC20Mock();
        swapper = makeAddr("swapper");
        ref = makeAddr("ref");
    }

    function test_distribute_zeroShareNoOp() public {
        uint256 total = 5 ether;
        uint32 shareBps = 0;

        token.mint(address(harness), total);

        vm.expectEmit(address(harness));
        emit Surplus(ref, swapper, address(token), total, 0);

        harness.distribute(ref, swapper, address(token), shareBps);

        assertEq(token.balanceOf(ref), 0);
        assertEq(token.balanceOf(swapper), total);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_distribute_zeroRecipientLeavesShareInHarness() public {
        uint256 total = 3 ether;
        uint32 shareBps = 1_500; // 15%
        uint256 expectedRefShare = (total * shareBps) / 10_000;

        token.mint(address(harness), total);

        vm.expectEmit(address(harness));
        emit Surplus(address(0), swapper, address(token), total, expectedRefShare);

        harness.distribute(address(0), swapper, address(token), shareBps);

        assertEq(token.balanceOf(address(0)), 0); // TokenLib.transfer short-circuits
        assertEq(token.balanceOf(swapper), total - expectedRefShare);
        assertEq(token.balanceOf(address(harness)), expectedRefShare);
    }

    function test_distribute_nonZeroShareSplitsBalances() public {
        uint256 total = 20 ether;
        uint32 shareBps = 2_500; // 25%
        uint256 expectedRefShare = (total * shareBps) / 10_000;

        token.mint(address(harness), total);

        vm.expectEmit(address(harness));
        emit Surplus(ref, swapper, address(token), total, expectedRefShare);

        harness.distribute(ref, swapper, address(token), shareBps);

        assertEq(token.balanceOf(ref), expectedRefShare);
        assertEq(token.balanceOf(swapper), total - expectedRefShare);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_distribute_zeroBalanceNoOp() public {
        vm.recordLogs();
        harness.distribute(ref, swapper, address(token), 1_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertEq(token.balanceOf(ref), 0);
        assertEq(token.balanceOf(swapper), 0);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_distribute_nativeTokenSplitsBalances() public {
        uint256 total = 1 ether;
        uint32 shareBps = 3_000; // 30%
        uint256 expectedRefShare = (total * shareBps) / 10_000;

        vm.deal(address(harness), total);

        vm.expectEmit(address(harness));
        emit Surplus(ref, swapper, address(0), total, expectedRefShare);

        uint256 refBefore = ref.balance;
        uint256 swapperBefore = swapper.balance;

        harness.distribute(ref, swapper, address(0), shareBps);

        assertEq(ref.balance, refBefore + expectedRefShare);
        assertEq(swapper.balance, swapperBefore + (total - expectedRefShare));
        assertEq(address(harness).balance, 0);
    }
}
