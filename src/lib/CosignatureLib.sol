// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";

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

    /// @dev Validates cosignature authenticity and data consistency for price attestation
    /// 1. Validates timestamp constraints (not future, within freshness window, vs epoch)
    /// 2. Ensures cosignature data matches order fields (reactor, chainid, cosigner, tokens)
    /// 3. Validates price data integrity (non-zero input/output values)
    /// 4. Checks signature validity using EIP-712 typed data hash verification
    function validate(CosignedOrder memory cosigned, address cosigner, address eip712) internal view {
        if (cosigned.cosignatureData.timestamp > block.timestamp) revert FutureCosignatureTimestamp();
        if (cosigned.order.freshness == 0) revert InvalidFreshness();
        if (cosigned.order.epoch != 0 && cosigned.order.freshness >= cosigned.order.epoch) {
            revert InvalidFreshnessVsEpoch();
        }
        if (cosigned.cosignatureData.reactor != cosigned.order.reactor) revert InvalidCosignatureReactor();
        if (cosigned.cosignatureData.chainid != cosigned.order.chainid) revert InvalidCosignatureChainid();
        if (cosigned.cosignatureData.cosigner != cosigner) revert InvalidCosignatureCosigner();
        if (cosigned.cosignatureData.input.token != cosigned.order.input.token) revert InvalidCosignatureInputToken();
        if (cosigned.cosignatureData.output.token != cosigned.order.output.token) {
            revert InvalidCosignatureOutputToken();
        }
        if (cosigned.cosignatureData.input.value == 0) revert InvalidCosignatureZeroInputValue();
        if (cosigned.cosignatureData.output.value == 0) revert InvalidCosignatureZeroOutputValue();

        if (cosigned.cosignatureData.timestamp + cosigned.order.freshness < block.timestamp) revert StaleCosignature();

        bytes32 digest = IEIP712(eip712).hashTypedData(OrderLib.hash(cosigned.cosignatureData));
        if (!SignatureChecker.isValidSignatureNow(cosigner, digest, cosigned.cosignature)) revert InvalidCosignature();
    }
}
