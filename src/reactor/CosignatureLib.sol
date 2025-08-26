// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {OrderLib} from "src/reactor/OrderLib.sol";

library CosignatureLib {
    error InvalidCosignature();
    error InvalidCosignatureInputToken();
    error InvalidCosignatureOutputToken();
    error InvalidCosignatureZeroInputValue();
    error InvalidCosignatureZeroOutputValue();
    error StaleCosignature();
    error FutureCosignatureTimestamp();
    error InvalidFreshness();
    error InvalidFreshnessVsEpoch();

    function validate(OrderLib.CosignedOrder memory cosigned, address cosigner, address eip712) internal view {
        if (cosigned.cosignatureData.timestamp > block.timestamp) revert FutureCosignatureTimestamp();
        if (cosigned.order.freshness == 0) revert InvalidFreshness();
        if (cosigned.order.epoch != 0 && cosigned.order.freshness >= cosigned.order.epoch) {
            revert InvalidFreshnessVsEpoch();
        }
        if (cosigned.cosignatureData.timestamp + cosigned.order.freshness < block.timestamp) revert StaleCosignature();
        if (cosigned.cosignatureData.input.token != cosigned.order.input.token) revert InvalidCosignatureInputToken();
        if (cosigned.cosignatureData.output.token != cosigned.order.output.token) {
            revert InvalidCosignatureOutputToken();
        }
        if (cosigned.cosignatureData.input.value == 0) revert InvalidCosignatureZeroInputValue();
        if (cosigned.cosignatureData.output.value == 0) revert InvalidCosignatureZeroOutputValue();

        bytes32 digest = IEIP712(eip712).hashTypedData(OrderLib.hash(cosigned.cosignatureData));
        if (!SignatureChecker.isValidSignatureNow(cosigner, digest, cosigned.cosignature)) revert InvalidCosignature();
    }
}
