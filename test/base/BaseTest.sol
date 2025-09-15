// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {BaseScript} from "script/base/BaseScript.sol";
import {DeployTestInfra} from "./DeployTestInfra.sol";

import {WM} from "src/WM.sol";
import {RePermit} from "src/repermit/RePermit.sol";
import {OrderLib} from "src/reactor/lib/OrderLib.sol";
import {SettlementLib} from "src/executor/lib/SettlementLib.sol";
import {Execution} from "src/Structs.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {Order, Input, Output, Exchange, CosignedOrder, Cosignature, CosignedValue} from "src/Structs.sol";

abstract contract BaseTest is Test, BaseScript, DeployTestInfra {
    address public multicall;

    address public wm;
    address public repermit;
    // Base vars used by helpers; suites may override
    address public reactor;
    address public adapter;
    address public executor;
    address public swapper;
    address public recipient;
    address public inToken;
    address public outToken;
    uint256 public inAmount;
    uint256 public inMax;
    uint256 public outAmount;
    uint256 public outMax;
    uint256 public cosignInValue;
    uint256 public cosignOutValue;
    uint32 public slippage;
    uint32 public freshness;

    ERC20Mock public token;
    ERC20Mock public token2;
    address public signer;
    uint256 public signerPK;
    address public other;

    uint256 internal _nextNonce;

    function setUp() public virtual override {
        super.setUp();
        multicall = deployTestInfra();

        wm = address(new WM(address(this)));
        vm.label(wm, "wm");

        repermit = address(new RePermit());
        vm.label(repermit, "repermit");

        token = new ERC20Mock();
        vm.label(address(token), "token");
        token2 = new ERC20Mock();
        vm.label(address(token2), "token2");

        (signer, signerPK) = makeAddrAndKey("signer");

        other = makeAddr("other");
        _nextNonce = 1;
        swapper = signer;
        recipient = signer;
        // Base tokens used across tests unless overridden
        inToken = address(token);
        outToken = address(token2);
        // Sensible defaults to reduce boilerplate in tests
        inAmount = 100;
        inMax = 100;
        outAmount = 100;
        outMax = 100;
        cosignInValue = 0;
        cosignOutValue = 0;
        slippage = 100;
        freshness = 1;
    }

    // helpers to manage WM allowlist in tests
    function allow(address who) internal {
        address[] memory addrs = new address[](1);
        addrs[0] = who;
        WM(wm).set(addrs, true);
    }

    function disallow(address who) internal {
        address[] memory addrs = new address[](1);
        addrs[0] = who;
        WM(wm).set(addrs, false);
    }

    function allowThis() internal {
        allow(address(this));
    }

    function disallowThis() internal {
        disallow(address(this));
    }

    // Single cosign helper using base vars
    function cosign(CosignedOrder memory co) internal view returns (CosignedOrder memory updated) {
        Cosignature memory c;
        c.timestamp = block.timestamp;
        c.chainid = block.chainid;
        c.reactor = co.order.reactor;
        c.cosigner = signer;
        c.input = CosignedValue({token: co.order.input.token, value: cosignInValue, decimals: 18});
        c.output = CosignedValue({token: co.order.output.token, value: cosignOutValue, decimals: 18});
        bytes32 digest = IEIP712(repermit).hashTypedData(OrderLib.hash(c));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);
        co.cosignatureData = c;
        co.cosignature = bytes.concat(r, s, bytes1(v));
        return co;
    }

    // Single order() helper: builds and signs using BaseTest vars
    function order() internal returns (CosignedOrder memory co) {
        co.order.reactor = reactor == address(0) ? address(this) : reactor;
        co.order.swapper = swapper == address(0) ? signer : swapper;
        co.order.nonce = _nextNonce;
        co.order.deadline = block.timestamp + 1 days;
        co.order.chainid = block.chainid;
        address _adapter = adapter == address(0) ? address(this) : adapter;
        co.order.exchange = Exchange({adapter: _adapter, ref: address(0), share: 0, data: hex""});
        co.order.executor = executor == address(0) ? address(this) : executor;
        co.order.exclusivity = 0;
        co.order.epoch = 0;
        co.order.slippage = slippage;
        co.order.freshness = freshness == 0 ? 1 : freshness;
        co.order.input = Input({token: inToken, amount: inAmount, maxAmount: inMax});
        co.order.output = Output({token: outToken, amount: outAmount, maxAmount: outMax, recipient: recipient});
        bytes32 digest = IEIP712(repermit).hashTypedData(OrderLib.hash(co.order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);
        co.signature = bytes.concat(r, s, bytes1(v));
        unchecked {
            _nextNonce++;
        }
    }

    // Single execution() helper
    function execution(uint256 minOut, address feeToken, uint256 feeAmount, address feeRecipient)
        internal
        pure
        returns (Execution memory ex)
    {
        ex = Execution({
            minAmountOut: minOut,
            fee: Output({token: feeToken, amount: feeAmount, recipient: feeRecipient, maxAmount: type(uint256).max}),
            data: hex""
        });
    }

    // uint256 private nonce;
    // address public ref = makeAddr("ref");
    // uint8 public refshare = 90;
    //
    // function signedOrder(
    //     address signer,
    //     uint256 signerPK,
    //     address inToken,
    //     address outToken,
    //     uint256 inAmount,
    //     uint256 outAmount,
    //     uint256 outAmountGas
    // ) internal returns (SignedOrder memory result) {
    //     ExclusiveDutchOrder memory order;
    //     {
    //         order.info.reactor = config.reactor;
    //         order.info.swapper = signer;
    //         order.info.nonce = nonce++;
    //         order.info.deadline = block.timestamp + 2 minutes;
    //         order.decayStartTime = block.timestamp + 1 minutes;
    //         order.decayEndTime = order.info.deadline;
    //
    //         order.exclusiveFiller = address(config.executor);
    //         order.info.additionalValidationContract = IValidationCallback(config.executor);
    //         order.info.additionalValidationData = abi.encode(ref, refshare);
    //
    //         order.input.token = ERC20(inToken);
    //         order.input.startAmount = inAmount;
    //         order.input.endAmount = inAmount;
    //
    //         order.outputs = new DutchOutput[](2);
    //         order.outputs[0] = DutchOutput(outToken, outAmount, outAmount * maxdecay / 100, signer);
    //         order.outputs[1] = DutchOutput(outToken, outAmountGas, outAmountGas, address(config.admin));
    //     }
    //
    //     result.sig = signOrder(signerPK, PERMIT2_ADDRESS, order);
    //     result.order = abi.encode(order);
    // }
}
