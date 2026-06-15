// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {DynamicP2DexAdapter} from "src/adapter/DynamicP2DexAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {MockPermit2} from "test/mocks/MockPermit2.sol";

contract DynamicP2DexAdapterTest is BaseTest {
    DynamicP2DexAdapter public adapterUut;
    MockDexRouter public routerA;
    MockDexRouter public routerB;
    MockPermit2 public permit2;

    function setUp() public override {
        super.setUp();
        routerA = new MockDexRouter();
        routerB = new MockDexRouter();
        permit2 = new MockPermit2();
        adapterUut = new DynamicP2DexAdapter(address(permit2));

        ERC20Mock(address(token)).mint(address(adapterUut), 2000 ether);
        adapter = address(adapterUut);
    }

    function test_swap_uses_dynamic_target_for_permit2_and_call() public {
        _swapThrough(address(routerA), 1000 ether);
        assertEq(ERC20Mock(address(token)).balanceOf(address(routerA)), 1000 ether);
        _assertPermit2Approval(address(routerA));

        _swapThrough(address(routerB), 500 ether);
        assertEq(ERC20Mock(address(token)).balanceOf(address(routerB)), 500 ether);
        _assertPermit2Approval(address(routerB));
    }

    function test_swap_reverts_invalid_target() public {
        inAmount = 1000 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        vm.expectRevert(IExchangeAdapter.InvalidTarget.selector);
        Execution memory x = executionWithTargetData(0, address(0), hex"");
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);
    }

    function _swapThrough(address target, uint256 amount) internal {
        inAmount = amount;
        inMax = amount;
        outAmount = amount / 2;
        triggerUpper = 0;
        CosignedOrder memory cosignedOrder = order();

        bytes memory data = abi.encodeWithSelector(
            MockDexRouter.doSwap.selector, address(token), amount, address(token2), amount, signer
        );

        bytes32 hash = OrderLib.hash(cosignedOrder.order);
        uint256 resolvedAmountOut = cosignedOrder.order.output.limit;
        Execution memory x = executionWithTargetData(0, target, data);
        adapterUut.delegateSwap(hash, resolvedAmountOut, cosignedOrder, x);

        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), target), 0);
        assertEq(ERC20Mock(address(token)).allowance(address(adapterUut), address(permit2)), 0);
    }

    function _assertPermit2Approval(address target) internal view {
        (address approvedToken, address approvedSpender, uint160 amount, uint48 expiration) = permit2.lastApproval();
        assertEq(approvedToken, address(token));
        assertEq(approvedSpender, target);
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
    }
}
