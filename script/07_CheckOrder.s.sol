// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {CosignedOrder, Execution, Exchange, Input, Output, CosignedValue, Cosignature} from "src/Structs.sol";
import {OrderReactor} from "src/OrderReactor.sol";
import {RePermit} from "src/RePermit.sol";
import {OrderLib} from "src/lib/OrderLib.sol";

import {Executor} from "src/Executor.sol";
import {WM} from "src/ops/WM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckOrder is Script, StdCheats {
    using stdJson for string;

    string private constant ORDER_PATH = "script/input/order.json";

    function run() external returns (bytes32 orderHash) {
        vm.createSelectFork(vm.envString("RPC_URL"));

        (CosignedOrder memory co, Execution memory x) = _loadOrder();
        _mockCosigner(co.cosignatureData.cosigner);

        orderHash = OrderLib.hash(co.order);

        _prepareInput(co);
        _prepareOutput(co);
        _execute(co, x);
    }

    function _prepareInput(CosignedOrder memory co) private {
        deal(co.order.input.token, co.order.swapper, co.order.input.maxAmount);
        hoax(co.order.swapper);
        IERC20(co.order.input.token)
            .approve(OrderReactor(payable(co.order.reactor)).repermit(), co.order.input.maxAmount);
    }

    function _prepareOutput(CosignedOrder memory co) private {
        if (co.order.output.token == address(0)) {
            deal(co.order.executor, type(uint256).max);
        } else {
            deal(co.order.output.token, co.order.executor, type(uint256).max);
        }
    }

    function _loadOrder() private view returns (CosignedOrder memory co, Execution memory x) {
        string memory json = vm.readFile(ORDER_PATH);
        console.log("Order JSON:");
        console.log(json);

        co.order.reactor = json.readAddress(".cosigned.order.reactor");
        co.order.executor = json.readAddress(".cosigned.order.executor");
        co.order.exchange = Exchange({
            adapter: json.readAddress(".cosigned.order.exchange.adapter"),
            ref: json.readAddress(".cosigned.order.exchange.ref"),
            share: uint32(json.readUint(".cosigned.order.exchange.share")),
            data: json.readBytes(".cosigned.order.exchange.data")
        });
        co.order.swapper = json.readAddress(".cosigned.order.swapper");
        co.order.nonce = json.readUint(".cosigned.order.nonce");
        co.order.deadline = json.readUint(".cosigned.order.deadline");
        co.order.chainid = json.readUint(".cosigned.order.chainid");
        co.order.exclusivity = uint32(json.readUint(".cosigned.order.exclusivity"));
        co.order.epoch = uint32(json.readUint(".cosigned.order.epoch"));
        co.order.slippage = uint32(json.readUint(".cosigned.order.slippage"));
        co.order.freshness = uint32(json.readUint(".cosigned.order.freshness"));
        co.order.input = Input({
            token: json.readAddress(".cosigned.order.input.token"),
            amount: json.readUint(".cosigned.order.input.amount"),
            maxAmount: json.readUint(".cosigned.order.input.maxAmount")
        });
        co.order.output = Output({
            token: json.readAddress(".cosigned.order.output.token"),
            limit: json.readUint(".cosigned.order.output.limit"),
            stop: json.readUint(".cosigned.order.output.stop"),
            recipient: json.readAddress(".cosigned.order.output.recipient")
        });

        co.signature = json.readBytes(".cosigned.signature");
        co.cosignature = json.readBytes(".cosigned.cosignature");

        co.cosignatureData.cosigner = json.readAddress(".cosigned.cosignatureData.cosigner");
        co.cosignatureData.reactor = json.readAddress(".cosigned.cosignatureData.reactor");
        co.cosignatureData.chainid = json.readUint(".cosigned.cosignatureData.chainid");
        co.cosignatureData.timestamp = json.readUint(".cosigned.cosignatureData.timestamp");
        co.cosignatureData.input = CosignedValue({
            token: json.readAddress(".cosigned.cosignatureData.input.token"),
            value: json.readUint(".cosigned.cosignatureData.input.value"),
            decimals: uint8(json.readUint(".cosigned.cosignatureData.input.decimals"))
        });
        co.cosignatureData.output = CosignedValue({
            token: json.readAddress(".cosigned.cosignatureData.output.token"),
            value: json.readUint(".cosigned.cosignatureData.output.value"),
            decimals: uint8(json.readUint(".cosigned.cosignatureData.output.decimals"))
        });

        x.minAmountOut = json.readUint(".execution.minAmountOut");
        x.fees = abi.decode(json.parseRaw(".execution.fees"), (Output[]));
        x.data = json.readBytes(".execution.data");
    }

    function _mockCosigner(address cosigner) private {
        vm.etch(cosigner, type(AlwaysValid1271).runtimeCode);
    }

    function _execute(CosignedOrder memory co, Execution memory x) private {
        Executor executor = Executor(payable(co.order.executor));
        hoax(WM(executor.wm()).owner());
        try executor.execute(co, x) {
        // no-op
        }
        catch (bytes memory reason) {
            console.log("execute reverted with reason:");
            console.logBytes(reason);
        }
    }
}

contract AlwaysValid1271 {
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return MAGIC_VALUE;
    }
}
