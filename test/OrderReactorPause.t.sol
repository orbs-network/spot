// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BaseTest} from "test/base/BaseTest.sol";
import {OrderReactor} from "src/reactor/OrderReactor.sol";
import {WMAllowed} from "src/lib/WMAllowed.sol";
import {CosignedOrder, Execution, Output} from "src/Structs.sol";

contract OrderReactorPauseTest is BaseTest {
    OrderReactor public reactorUut;
    address public allowedUser;
    address public notAllowedUser;

    function setUp() public override {
        super.setUp();
        reactorUut = new OrderReactor(repermit, signer, wm);
        allowedUser = makeAddr("allowedUser");
        notAllowedUser = makeAddr("notAllowedUser");

        // Allow the test contract and allowedUser in WM
        allowThis();
        allow(allowedUser);
    }

    function test_pause_allowed_user_can_pause() public {
        assertFalse(reactorUut.paused());

        vm.prank(allowedUser);
        reactorUut.pause();

        assertTrue(reactorUut.paused());
    }

    function test_pause_reverts_when_not_allowed() public {
        assertFalse(reactorUut.paused());

        vm.prank(notAllowedUser);
        vm.expectRevert(WMAllowed.NotAllowed.selector);
        reactorUut.pause();

        assertFalse(reactorUut.paused());
    }

    function test_unpause_allowed_user_can_unpause() public {
        // First pause the reactor
        vm.prank(allowedUser);
        reactorUut.pause();
        assertTrue(reactorUut.paused());

        // Then unpause it
        vm.prank(allowedUser);
        reactorUut.unpause();
        assertFalse(reactorUut.paused());
    }

    function test_unpause_reverts_when_not_allowed() public {
        // First pause the reactor as allowed user
        vm.prank(allowedUser);
        reactorUut.pause();
        assertTrue(reactorUut.paused());

        // Try to unpause as non-allowed user
        vm.prank(notAllowedUser);
        vm.expectRevert(WMAllowed.NotAllowed.selector);
        reactorUut.unpause();

        assertTrue(reactorUut.paused());
    }

    function test_executeWithCallback_reverts_when_paused() public {
        // Set up a valid order with the correct reactor
        inToken = address(token);
        outToken = address(token2);
        inAmount = 100;
        inMax = 100;
        outAmount = 50;
        outMax = type(uint256).max;
        reactor = address(reactorUut); // Set the reactor to our test reactor
        cosignInValue = 200e6; // Set valid cosign values
        cosignOutValue = 100e18;

        CosignedOrder memory co = order();
        Execution memory ex = Execution({
            minAmountOut: 0,
            fee: Output({token: address(0), limit: 0, stop: 0, recipient: address(0)}),
            data: ""
        });

        // Pause the reactor
        vm.prank(allowedUser);
        reactorUut.pause();

        // Fund the order input
        fundOrderInput(co);

        // Try to execute - should revert
        co = cosign(co);
        vm.expectRevert("Pausable: paused");
        reactorUut.executeWithCallback(co, ex);
    }
}

// Simple callback contract for testing
contract SimpleCallback {
    function reactorCallback(
        bytes32, // orderHash
        uint256, // resolvedAmountOut
        CosignedOrder calldata, // cosignedOrder
        Execution calldata // execution
    ) external {
        // Simple implementation that will fail
        revert("SimpleCallback: not implemented");
    }
}
