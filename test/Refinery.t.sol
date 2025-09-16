// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {BaseTest} from "test/base/BaseTest.sol";
import {Refinery} from "src/Refinery.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

contract RefineryTest is BaseTest {
    Refinery internal refinery;

    event Refined(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public virtual override {
        super.setUp();
        refinery = new Refinery(wm);
    }

    function test_cant_execute_if_not_allowed() public {
        disallowThis();
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](0);
        vm.expectRevert(Refinery.NotAllowed.selector);
        refinery.execute(calls);
    }

    function test_cant_transfer_if_not_allowed() public {
        disallowThis();
        vm.expectRevert(Refinery.NotAllowed.selector);
        refinery.transfer(address(token), other, 100);
    }

    function test_execute() public {
        allowThis();
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(token),
            allowFailure: false,
            callData: abi.encodeWithSignature("mint(address,uint256)", other, 1e18)
        });
        refinery.execute(calls);
        assertEq(token.balanceOf(other), 1e18);
    }

    function test_execute_empty_calls_ok() public {
        allowThis();
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](0);
        refinery.execute(calls);
        // nothing to assert beyond not reverting
    }

    function test_execute_call_failure_allowFailure_true_does_not_revert() public {
        allowThis();
        // Attempt to transfer tokens from refinery without balance -> underlying call fails
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(token),
            allowFailure: true,
            callData: abi.encodeWithSignature("transfer(address,uint256)", other, 1e18)
        });
        refinery.execute(calls);
    }

    function test_execute_call_failure_allowFailure_false_reverts() public {
        allowThis();
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(token),
            allowFailure: false,
            callData: abi.encodeWithSignature("transfer(address,uint256)", other, 1e18)
        });
        vm.expectRevert();
        refinery.execute(calls);
    }

    function test_transfer_eth() public {
        allowThis();
        vm.deal(address(refinery), 1e18);
        refinery.transfer(address(0), other, 5_000); // 50%
        assertEq(other.balance, 0.5e18);
    }

    function test_transfer_eth_bps_zero_noop() public {
        allowThis();
        vm.deal(address(refinery), 1e18);
        refinery.transfer(address(0), other, 0); // 0%
        assertEq(other.balance, 0);
    }

    function test_transfer_eth_bps_full() public {
        allowThis();
        vm.deal(address(refinery), 1e18);
        refinery.transfer(address(0), other, 10_000); // 100%
        assertEq(other.balance, 1e18);
    }

    function test_transfer_eth_zero_balance() public {
        allowThis();
        refinery.transfer(address(0), other, 5_000); // 50%
        assertEq(other.balance, 0);
    }

    function test_transfer_erc20() public {
        allowThis();
        token.mint(address(refinery), 1e18);
        refinery.transfer(address(token), other, 5_000); // 50%
        assertEq(token.balanceOf(other), 0.5e18);
    }

    function test_transfer_erc20_bps_zero_noop() public {
        allowThis();
        token.mint(address(refinery), 1e18);
        refinery.transfer(address(token), other, 0); // 0%
        assertEq(token.balanceOf(other), 0);
    }

    function test_transfer_erc20_bps_full() public {
        allowThis();
        token.mint(address(refinery), 1e18);
        refinery.transfer(address(token), other, 10_000); // 100%
        assertEq(token.balanceOf(other), 1e18);
    }

    function test_transfer_erc20_zero_balance() public {
        allowThis();
        refinery.transfer(address(token), other, 5_000); // 50%
        assertEq(token.balanceOf(other), 0);
    }

    function test_receive() public {
        (bool success,) = address(refinery).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(refinery).balance, 1 ether);
    }

    function test_event_refined_eth() public {
        allowThis();
        vm.deal(address(refinery), 1e18);
        vm.expectEmit(true, true, true, true);
        emit Refined(address(0), other, 0.5e18);
        refinery.transfer(address(0), other, 5_000); // 50%
    }

    function test_no_event_when_amount_zero_eth() public {
        allowThis();
        vm.recordLogs();
        refinery.transfer(address(0), other, 0); // 0%
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // No Refined event should be emitted
        assertEq(entries.length, 0);
    }

    function test_event_refined_erc20() public {
        allowThis();
        token.mint(address(refinery), 1e18);
        vm.expectEmit(true, true, true, true);
        emit Refined(address(token), other, 0.5e18);
        refinery.transfer(address(token), other, 5_000); // 50%
    }

    function test_no_event_when_amount_zero_erc20() public {
        allowThis();
        vm.recordLogs();
        refinery.transfer(address(token), other, 0); // 0%
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }
}
