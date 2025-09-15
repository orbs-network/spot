// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {BaseTest} from "test/base/BaseTest.sol";
import {Executor} from "src/executor/Executor.sol";
import {OrderReactor} from "src/reactor/OrderReactor.sol";
import {DefaultDexAdapter} from "src/adapter/DefaultDexAdapter.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {Execution} from "src/Structs.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {RePermitLib} from "src/repermit/RePermitLib.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockDexRouter} from "test/mocks/MockDexRouter.sol";
import {CosignedOrder, Output} from "src/Structs.sol";
import {SwapAdapterMock} from "test/mocks/SwapAdapter.sol";

contract OrderReactorE2ETest is BaseTest {
    OrderReactor public reactorUut;
    Executor public exec;
    DefaultDexAdapter public adapterUut;
    MockDexRouter public router;

    function setUp() public override {
        super.setUp();
        reactorUut = new OrderReactor(repermit, signer);
        allowThis();
        exec = new Executor(address(reactorUut), wm);
        allow(address(exec));

        router = new MockDexRouter();
        adapterUut = new DefaultDexAdapter(address(router));

        reactor = address(reactorUut);
        executor = address(exec);
        adapter = address(adapterUut);
        recipient = signer;
        slippage = 0;
        freshness = 300;
    }

    function _signRepermitForSpender(bytes32 witness, address spender, CosignedOrder memory co)
        internal
        view
        returns (bytes memory)
    {
        RePermitLib.RePermitTransferFrom memory permit;
        permit.permitted = RePermitLib.TokenPermissions({token: co.order.input.token, amount: co.order.input.maxAmount});
        permit.nonce = co.order.nonce;
        permit.deadline = co.order.deadline;

        bytes32 structHash = RePermitLib.hashWithWitness(permit, witness, OrderLib.WITNESS_TYPE_SUFFIX, spender);
        bytes32 digest = IEIP712(repermit).hashTypedData(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);
        return bytes.concat(r, s, bytes1(v));
    }

    function test_e2e_erc20_end_to_end_minOut_delta_and_pull_from_executor() public {
        inToken = address(token);
        outToken = address(token2);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 500 ether;
        outMax = type(uint256).max;

        CosignedOrder memory co = order();

        ERC20Mock(address(token)).mint(signer, inAmount);
        hoax(signer);
        ERC20Mock(address(token)).approve(repermit, inAmount);

        ERC20Mock(address(token2)).mint(address(exec), 600 ether);

        cosignInValue = 1000;
        cosignOutValue = 600;
        co = cosign(co);

        bytes32 orderHash = OrderLib.hash(co.order);
        co.signature = _signRepermitForSpender(orderHash, address(reactorUut), co);

        Execution memory ex = Execution({
            minAmountOut: 600 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: abi.encodeWithSelector(MockDexRouter.doSwap.selector, inToken, inAmount, outToken, 0, address(exec))
        });

        uint256 before = ERC20Mock(outToken).balanceOf(recipient);
        exec.execute(co, ex);

        assertEq(ERC20Mock(outToken).balanceOf(recipient), before + 600 ether);
        assertEq(ERC20Mock(outToken).allowance(address(exec), address(reactorUut)), 0);
    }

    function test_e2e_eth_end_to_end_minOut_delta_and_refund() public {
        inToken = address(token);
        outToken = address(0);
        inAmount = 1 ether;
        inMax = inAmount;
        outAmount = 1 ether;
        outMax = type(uint256).max;
        adapter = address(new SwapAdapterMock());
        CosignedOrder memory co = order();

        ERC20Mock(address(token)).mint(signer, inAmount);
        hoax(signer);
        ERC20Mock(address(token)).approve(repermit, inAmount);

        vm.deal(address(exec), 1 ether);

        cosignInValue = 100;
        cosignOutValue = 100;
        co = cosign(co);
        bytes32 orderHash = OrderLib.hash(co.order);
        co.signature = _signRepermitForSpender(orderHash, address(reactorUut), co);

        Execution memory ex = Execution({
            minAmountOut: 1 ether,
            fee: Output({token: address(0), amount: 0, recipient: address(0), maxAmount: type(uint256).max}),
            data: hex""
        });

        uint256 before = recipient.balance;
        exec.execute(co, ex);
        assertEq(recipient.balance - before, 1 ether);
        assertEq(address(reactorUut).balance, 0);
    }
}
