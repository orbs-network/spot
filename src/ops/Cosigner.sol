// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICommitteeSync} from "src/interface/ICommitteeSync.sol";

/// @title Cosigner
/// @notice Contract-based cosigner that validates signers against CommitteeSync config
/// @dev Signer approval is read at runtime via CommitteeSync config(bytes32 key, address signer)
/// @dev The current contract owner is always considered approved
/// @dev Implements ERC-1271 for contract signature validation
contract Cosigner is AbstractSigner, IERC1271, Ownable {
    /// @dev ERC-1271 magic value for valid signatures - computed as bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 private constant ERC1271_MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @notice Committee key used to query signer expiration config
    /// @dev Versioned domain-style key for committee config compatibility
    bytes32 public constant KEY = keccak256("spot.cosigner.expires.v1");

    /// @notice CommitteeSync contract for signer configuration
    ICommitteeSync public immutable committee;

    error InvalidCosignature();
    error InvalidCommittee();

    /// @notice Constructs the Cosigner contract with CommitteeSync address and owner
    /// @param committee_ CommitteeSync contract used for runtime signer checks
    /// @param owner_ Owner address that is always considered approved
    constructor(address committee_, address owner_) Ownable(owner_) {
        if (committee_ == address(0)) revert InvalidCommittee();
        committee = ICommitteeSync(committee_);
    }

    /// @notice Checks if a signer is currently approved and not expired
    /// @dev Reads signer config from CommitteeSync and decodes config bytes as uint256 expiration
    /// @param signer The address to check
    /// @return True if the signer is approved and not expired
    function isApprovedNow(address signer) public view returns (bool) {
        if (owner() != address(0) && signer == owner()) return true;

        bytes memory configData = committee.config(KEY, signer);
        if (configData.length != 32) return false;
        uint256 signerExpiration = abi.decode(configData, (uint256));
        return signerExpiration > block.timestamp;
    }

    /// @notice Validates that a signature was created by an approved signer
    /// @dev Implements AbstractSigner's signature validation interface
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return True if the signature was created by an approved and non-expired signer
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature) internal view override returns (bool) {
        return isApprovedNow(ECDSA.recover(hash, signature));
    }

    /// @notice Validates that a signature was created by an approved signer (ERC-1271)
    /// @dev Implements IERC1271.isValidSignature for contract signature validation
    /// @dev Reverts with InvalidCosignature if signature is not valid
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return magicValue The ERC-1271 magic value if valid
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        if (!_rawSignatureValidation(hash, signature)) revert InvalidCosignature();
        return ERC1271_MAGIC_VALUE;
    }
}
