// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title Cosigner
/// @notice Contract-based cosigner that manages approved signers with time-to-live (TTL)
/// @dev Extends AbstractSigner and Ownable2Step to provide secure ownership management
/// @dev Owner can approve/revoke signers. Signers can create valid signatures until their TTL expires
/// @dev Implements ERC-1271 for contract signature validation
contract Cosigner is AbstractSigner, Ownable2Step, IERC1271 {
    /// @dev ERC-1271 magic value for valid signatures - computed as bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 private constant ERC1271_MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @dev Invalid signature return value
    bytes4 private constant INVALID_SIGNATURE = 0xffffffff;

    /// @notice Mapping of approved signer addresses to their expiration timestamp
    /// @dev Timestamp of 0 means the signer is not approved
    mapping(address => uint256) public approvedSigners;

    /// @notice Emitted when a signer is approved
    event SignerApproved(address indexed signer, uint256 expiresAt);

    /// @notice Emitted when a signer is revoked
    event SignerRevoked(address indexed signer);

    error SignerNotApproved();
    error SignerExpired();

    /// @notice Constructs the Cosigner contract with an initial owner
    /// @param initialOwner The address that will be the initial owner (not a signer by default)
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Approves a signer with a time-to-live (TTL)
    /// @dev Only the owner can approve signers
    /// @param signer The address to approve as a signer
    /// @param ttl Time-to-live in seconds from now
    function approveSigner(address signer, uint256 ttl) external onlyOwner {
        uint256 expiresAt = block.timestamp + ttl;
        approvedSigners[signer] = expiresAt;
        emit SignerApproved(signer, expiresAt);
    }

    /// @notice Revokes a signer's approval
    /// @dev Only the owner can revoke signers
    /// @param signer The address to revoke
    function revokeSigner(address signer) external onlyOwner {
        delete approvedSigners[signer];
        emit SignerRevoked(signer);
    }

    /// @notice Checks if a signer is currently approved and not expired
    /// @param signer The address to check
    /// @return True if the signer is approved and not expired
    function isSignerApproved(address signer) public view returns (bool) {
        uint256 expiresAt = approvedSigners[signer];
        return expiresAt > 0 && block.timestamp < expiresAt;
    }

    /// @notice Validates that a signature was created by an approved signer (ERC-1271)
    /// @dev Implements IERC1271.isValidSignature for contract signature validation
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return magicValue The ERC-1271 magic value if valid, INVALID_SIGNATURE otherwise
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        if (_rawSignatureValidation(hash, signature)) {
            return ERC1271_MAGIC_VALUE;
        }
        return INVALID_SIGNATURE;
    }

    /// @notice Validates that a signature was created by an approved signer
    /// @dev Implements AbstractSigner's signature validation interface
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return True if the signature was created by an approved and non-expired signer
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature) internal view override returns (bool) {
        try this.recoverSigner(hash, signature) returns (address recovered) {
            return isSignerApproved(recovered);
        } catch {
            return false;
        }
    }

    /// @notice Recovers the signer from a signature
    /// @dev External function to allow try-catch in _rawSignatureValidation
    /// @param hash The hash that was signed
    /// @param signature The signature to validate
    /// @return The recovered signer address
    function recoverSigner(bytes32 hash, bytes calldata signature) external pure returns (address) {
        return ECDSA.recover(hash, signature);
    }
}
