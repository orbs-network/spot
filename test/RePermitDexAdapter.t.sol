// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExchangeAdapter} from "src/interface/IExchangeAdapter.sol";
import {RePermitDexAdapter} from "src/adapter/RePermitDexAdapter.sol";
import {CosignedOrder, Execution, Order} from "src/Structs.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {RePermitLib} from "src/lib/RePermitLib.sol";
import {BaseTest} from "test/base/BaseTest.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IEIP712} from "src/interface/IEIP712.sol";

contract RePermitDexAdapterTest is BaseTest {
    RePermitDexAdapter public adapterUut;
    address public mm;
    uint256 public mmPk;

    function setUp() public override {
        super.setUp();
        (mm, mmPk) = makeAddrAndKey("mm");
        adapterUut = new RePermitDexAdapter(repermit, mm);
        adapter = address(adapterUut);
    }

    function test_repermit_swap_success() public {
        // User wants to swap 100 token -> 50 token2
        inAmount = 100 ether;
        inMax = 100 ether;
        outAmount = 50 ether;
        outMax = 50 ether;

        CosignedOrder memory cosignedOrder = order();
        bytes32 orderHash = OrderLib.hash(cosignedOrder.order);

        // MM provides liquidity
        // MM has token2, wants token
        ERC20Mock(address(token2)).mint(mm, 1000 ether);
        // Adapter (Executor) has token (from user)
        ERC20Mock(address(token)).mint(address(adapterUut), 100 ether);

        // MM must approve RePermit (or permit2 pattern)
        // RePermit uses safeTransferFrom, so MM must approve RePermit to spend token2
        vm.prank(mm);
        ERC20Mock(address(token2)).approve(repermit, type(uint256).max);

        // MM signs a RePermit witness transfer
        // Permitting adapterUut to spend 50 token2, bounded by orderHash
        RePermitLib.RePermitTransferFrom memory permit = RePermitLib.RePermitTransferFrom({
            permitted: RePermitLib.TokenPermissions({token: address(token2), amount: 50 ether}),
            nonce: 0,
            deadline: cosignedOrder.order.deadline
        });

        bytes32 witness = orderHash;
        // hashRePermit helper in BaseTest might need adjustment or we call RePermitLib directly
        // BaseTest.hashRePermit calls RePermitLib.hashWithWitness
        bytes32 digest = IEIP712(repermit)
            .hashTypedData(
                RePermitLib.hashWithWitness(
                    permit,
                    witness,
                    OrderLib.WITNESS_TYPE_SUFFIX,
                    address(adapterUut) // spender
                )
            );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mmPk, digest);
        bytes memory signature = bytes.concat(r, s, bytes1(v));

        bytes memory data = abi.encode(signature);
        Execution memory x = executionWithData(outAmount, data);

        // Execute
        adapterUut.delegateSwap(orderHash, outAmount, cosignedOrder, x);

        // Assertions
        // Adapter should have received 50 token2
        assertEq(ERC20Mock(address(token2)).balanceOf(address(adapterUut)), 50 ether);
        // MM should have received 100 token
        assertEq(ERC20Mock(address(token)).balanceOf(mm), 100 ether);
    }
}
