// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

// Before: Had to import OrderLib and qualify each struct with OrderLib.StructName
// import {OrderLib} from "src/reactor/lib/OrderLib.sol";

// After: Can directly import the structs we need
import {Order, CosignedOrder, Input, Output, Exchange, OrderInfo} from "src/reactor/lib/OrderStructs.sol";

/// @notice Test to demonstrate the improved import ergonomics after extracting structs
contract StructImportErgonomicsTest is Test {
    function test_direct_struct_usage() public {
        // Before: OrderLib.Order memory order;
        // After: Order memory order;
        Order memory order;
        
        // Before: OrderLib.CosignedOrder memory co;
        // After: CosignedOrder memory co;
        CosignedOrder memory co;
        
        // Before: OrderLib.Input memory input;
        // After: Input memory input;
        Input memory input;
        
        // Before: OrderLib.Output memory output;
        // After: Output memory output;
        Output memory output;
        
        // Before: OrderLib.Exchange memory exchange;
        // After: Exchange memory exchange;
        Exchange memory exchange;
        
        // Before: OrderLib.OrderInfo memory info;
        // After: OrderInfo memory info;
        OrderInfo memory info;
        
        // This demonstrates the improved import ergonomics
        assertTrue(true);
    }
}