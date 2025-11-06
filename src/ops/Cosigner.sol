// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title Cosigner
/// @notice Contract-based cosigner that uses OpenZeppelin's AbstractSigner pattern with ERC-1271 support
/// @dev Extends AbstractSigner and Ownable2Step to provide secure ownership management
/// @dev Verifies that signatures are signed by the current owner
/// @dev Implements ERC-1271 for contract signature validation
contract Cosigner is AbstractSigner, Ownable2Step, IERC1271 {
    /// @dev ERC-1271 magic value for valid signatures
    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Constructs the Cosigner contract with an initial owner
    /// @param initialOwner The address that will be the initial owner and signer
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Validates that a signature was created by the current owner (ERC-1271)
    /// @dev Implements IERC1271.isValidSignature for contract signature validation
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return magicValue The ERC-1271 magic value if valid, 0xffffffff otherwise
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        if (_rawSignatureValidation(hash, signature)) {
            return ERC1271_MAGIC_VALUE;
        }
        return 0xffffffff;
    }

    /// @notice Validates that a signature was created by the current owner
    /// @dev Implements AbstractSigner's signature validation interface
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (ECDSA format: r, s, v)
    /// @return True if the signature was created by the current owner, false otherwise
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature) internal view override returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        return owner() == recovered && err == ECDSA.RecoverError.NoError;
    }

    /// @notice Returns the address that can sign on behalf of this contract
    /// @dev This is the current owner of the contract
    /// @return The address of the current owner/signer
    function signer() public view returns (address) {
        return owner();
    }
}
