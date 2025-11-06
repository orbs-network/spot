// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title Cosigner
/// @notice Contract-based cosigner that manages approved signers with expiration deadlines
/// @dev Extends AbstractSigner and Ownable2Step to provide secure ownership management
/// @dev Owner can approve/revoke signers. Signers can create valid signatures until their deadline expires
/// @dev Implements ERC-1271 for contract signature validation
contract Cosigner is AbstractSigner, Ownable2Step, IERC1271 {
    /// @dev ERC-1271 magic value for valid signatures - computed as bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 private constant ERC1271_MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @notice Mapping of signer addresses to their expiration timestamp
    /// @dev Timestamp of 0 means the signer is not approved
    mapping(address => uint256) public signers;

    /// @notice Emitted when a signer is approved
    event SignerApproved(address indexed signer, uint256 deadline);

    /// @notice Emitted when a signer is revoked
    event SignerRevoked(address indexed signer);

    error InvalidCosignature();

    /// @notice Constructs the Cosigner contract with an initial owner
    /// @param initialOwner The address that will be the initial owner (not a signer by default)
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Approves a signer with a deadline timestamp
    /// @dev Only the owner can approve signers
    /// @param signer The address to approve as a signer
    /// @param deadline The expiration timestamp (not computed, directly assigned)
    function approve(address signer, uint256 deadline) external onlyOwner {
        signers[signer] = deadline;
        emit SignerApproved(signer, deadline);
    }

    /// @notice Revokes a signer's approval
    /// @dev Only the owner can revoke signers
    /// @param signer The address to revoke
    function revokeSigner(address signer) external onlyOwner {
        signers[signer] = 0;
        emit SignerRevoked(signer);
    }

    /// @notice Checks if a signer is currently approved and not expired
    /// @param signer The address to check
    /// @return True if the signer is approved and not expired
    function isApprovedNow(address signer) public view returns (bool) {
        return block.timestamp < signers[signer];
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
        if (!_rawSignatureValidation(hash, signature)) {
            revert InvalidCosignature();
        }
        return ERC1271_MAGIC_VALUE;
    }
}
