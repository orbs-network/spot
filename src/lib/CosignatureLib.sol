// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder, Cosignature} from "src/Structs.sol";

/// @title Cosignature validation library
/// @notice Validates cosigned price attestations with freshness windows and proper token validation
library CosignatureLib {
    error InvalidCosignature();
    error InvalidCosignatureInputToken();
    error InvalidCosignatureOutputToken();
    error InvalidCosignatureZeroInputValue();
    error InvalidCosignatureZeroOutputValue();
    error InvalidCosignatureReactor();
    error InvalidCosignatureChainid();
    error InvalidCosignatureCosigner();
    error StaleCosignature();
    error FutureCosignatureTimestamp();
    error InvalidFreshness();
    error InvalidFreshnessVsEpoch();
    error TriggerBeforeStart();
    error TriggerAfterCurrent();

    /// @dev Validates cosignature authenticity and data consistency for price attestation
    /// 1. Validates trigger cosignature (signature/data consistency, no freshness window)
    /// 2. Validates current cosignature (signature/data consistency + freshness window)
    /// 3. Enforces trigger timestamp ordering against order.start and current timestamp
    function validate(CosignedOrder memory cosigned, address cosigner, address eip712) internal view {
        if (cosigned.order.freshness == 0) revert InvalidFreshness();
        if (cosigned.order.epoch != 0 && cosigned.order.freshness >= cosigned.order.epoch) {
            revert InvalidFreshnessVsEpoch();
        }

        _validateCosignature(cosigned.trigger, cosigned.triggerCosignature, cosigned, cosigner, eip712);
        _validateCosignature(cosigned.current, cosigned.currentCosignature, cosigned, cosigner, eip712);

        if (cosigned.trigger.timestamp < cosigned.order.start) revert TriggerBeforeStart();
        if (cosigned.trigger.timestamp > cosigned.current.timestamp) revert TriggerAfterCurrent();
        if (cosigned.current.timestamp + cosigned.order.freshness < block.timestamp) revert StaleCosignature();
    }

    function _validateCosignature(
        Cosignature memory data,
        bytes memory signature,
        CosignedOrder memory cosigned,
        address cosigner,
        address eip712
    ) private view {
        if (data.timestamp > block.timestamp) revert FutureCosignatureTimestamp();
        if (data.chainid != cosigned.order.chainid) revert InvalidCosignatureChainid();
        if (data.reactor != cosigned.order.reactor) revert InvalidCosignatureReactor();
        if (data.cosigner != cosigner) revert InvalidCosignatureCosigner();
        if (data.input.token != cosigned.order.input.token) revert InvalidCosignatureInputToken();
        if (data.output.token != cosigned.order.output.token) revert InvalidCosignatureOutputToken();
        if (data.input.value == 0) revert InvalidCosignatureZeroInputValue();
        if (data.output.value == 0) revert InvalidCosignatureZeroOutputValue();

        bytes32 digest = IEIP712(eip712).hashTypedData(OrderLib.hash(data));
        if (!SignatureChecker.isValidSignatureNow(cosigner, digest, signature)) revert InvalidCosignature();
    }
}
