// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Executor} from "src/Executor.sol";
import {ApprovalDexAdapter} from "src/adapter/ApprovalDexAdapter.sol";
import {UniversalAdapter} from "src/adapter/UniversalAdapter.sol";
import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {Execution, CosignedOrder} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {USDTMock} from "test/mocks/USDTMock.sol";
import {MockParaswapAugustus, MockTokenTransferProxy} from "test/mocks/MockParaswap.sol";
import {MockReactor} from "test/mocks/MockReactor.sol";

contract ApprovalDexAdapterTest is BaseTest {
    ApprovalDexAdapter selectedAdapter;
    MockParaswapAugustus router;
    MockTokenTransferProxy spender;
    Executor exec;

    function setUp() public override {
        super.setUp();
        spender = new MockTokenTransferProxy();
        router = new MockParaswapAugustus(spender);
        selectedAdapter = new ApprovalDexAdapter(address(router), address(spender));
        reactor = address(new MockReactor());
        exec = new Executor(reactor, wm);
        executor = address(exec);
        adapter = address(new UniversalAdapter());
        inAmount = 100 ether;
        inMax = inAmount;
        outAmount = 50 ether;
        triggerUpper = 0;
        ERC20Mock(address(token)).mint(address(exec), inAmount);
    }

    function swap(address target, uint256 spendAmount) external {
        CosignedOrder memory co = order();
        bytes memory data =
            abi.encodeCall(router.doSwap, (inToken, spendAmount, address(token2), 200 ether, address(exec)));
        Execution memory inner = executionWithTargetData(0, target, data);
        Execution memory outer = executionWithTargetData(0, address(selectedAdapter), abi.encode(inner));
        vm.prank(reactor);
        exec.reactorCallback(OrderLib.hash(co.order), outAmount, co, outer);
    }

    function test_universal_swap_approves_separate_spender_and_clears_remainder() public {
        this.swap(address(router), 80 ether);
        assertEq(token.balanceOf(address(router)), 80 ether);
        assertEq(token.balanceOf(address(exec)), 20 ether);
        assertEq(token2.balanceOf(address(exec)), 200 ether);
        assertEq(token.allowance(address(exec), address(spender)), 0);
        assertEq(token.allowance(address(exec), address(router)), 0);
    }

    function test_swap_handles_existing_USDT_allowance() public {
        USDTMock usdt = new USDTMock();
        inToken = address(usdt);
        usdt.mint(address(exec), inAmount);
        vm.prank(address(exec));
        usdt.approve(address(spender), 1);
        this.swap(address(router), 80 ether);
        assertEq(usdt.balanceOf(address(router)), 80 ether);
        assertEq(usdt.allowance(address(exec), address(spender)), 0);
    }

    function test_swap_rejects_other_target() public {
        vm.expectRevert(IExchangeAdapter.InvalidTarget.selector);
        this.swap(address(spender), inAmount);
    }

    function test_swap_reverts_router_failure() public {
        router.setShouldFail(true);
        vm.expectRevert("Mock ParaSwap swap failed");
        this.swap(address(router), inAmount);
        assertEq(token.allowance(address(exec), address(spender)), 0);
    }

    function test_swap_cannot_spend_more_than_order_input() public {
        ERC20Mock(address(token)).mint(address(exec), 1);
        vm.expectRevert();
        this.swap(address(router), inAmount + 1);
    }
}
