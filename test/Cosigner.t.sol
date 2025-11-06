// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import {Cosigner} from "src/ops/Cosigner.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract CosignerTest is Test {
    Cosigner public cosigner;
    CosignerWrapper public wrapper;
    address public initialOwner;
    uint256 public initialOwnerPK;
    address public newOwner;
    uint256 public newOwnerPK;
    address public unauthorized;

    function setUp() public {
        (initialOwner, initialOwnerPK) = makeAddrAndKey("initialOwner");
        (newOwner, newOwnerPK) = makeAddrAndKey("newOwner");
        unauthorized = makeAddr("unauthorized");

        cosigner = new Cosigner(initialOwner);
        wrapper = new CosignerWrapper(initialOwner);
    }

    function test_constructor_sets_initial_owner() public view {
        assertEq(cosigner.owner(), initialOwner);
    }

    function test_signer_returns_current_owner() public view {
        assertEq(cosigner.signer(), initialOwner);
    }

    function test_rawSignatureValidation_accepts_owner_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(initialOwnerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool valid = wrapper.validateSignature(hash, signature);
        assertTrue(valid);
    }

    function test_rawSignatureValidation_rejects_non_owner_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newOwnerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool valid = wrapper.validateSignature(hash, signature);
        assertFalse(valid);
    }

    function test_rawSignatureValidation_rejects_invalid_signature() public view {
        bytes32 hash = keccak256("test message");
        bytes memory signature =
            hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        bool valid = wrapper.validateSignature(hash, signature);
        assertFalse(valid);
    }

    function test_transferOwnership_initiates_two_step_transfer() public {
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);

        // Owner should still be the initial owner
        assertEq(cosigner.owner(), initialOwner);
        // Pending owner should be set
        assertEq(cosigner.pendingOwner(), newOwner);
    }

    function test_acceptOwnership_completes_transfer() public {
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);

        vm.prank(newOwner);
        cosigner.acceptOwnership();

        assertEq(cosigner.owner(), newOwner);
        assertEq(cosigner.pendingOwner(), address(0));
    }

    function test_signer_updates_after_ownership_transfer() public {
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);

        vm.prank(newOwner);
        cosigner.acceptOwnership();

        assertEq(cosigner.signer(), newOwner);
    }

    function test_signature_validation_uses_new_owner_after_transfer() public {
        // Transfer ownership
        vm.prank(initialOwner);
        wrapper.transferOwnership(newOwner);

        vm.prank(newOwner);
        wrapper.acceptOwnership();

        bytes32 hash = keccak256("test message");

        // Old owner's signature should now be invalid
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(initialOwnerPK, hash);
        bytes memory oldOwnerSig = abi.encodePacked(r1, s1, v1);
        assertFalse(wrapper.validateSignature(hash, oldOwnerSig));

        // New owner's signature should be valid
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(newOwnerPK, hash);
        bytes memory newOwnerSig = abi.encodePacked(r2, s2, v2);
        assertTrue(wrapper.validateSignature(hash, newOwnerSig));
    }

    function test_transferOwnership_reverts_when_not_owner() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.transferOwnership(newOwner);
    }

    function test_acceptOwnership_reverts_when_not_pending_owner() public {
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.acceptOwnership();
    }

    function test_transferOwnership_to_zero_address_cancels_pending() public {
        // First initiate transfer
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);
        assertEq(cosigner.pendingOwner(), newOwner);

        // Then cancel by transferring to zero address
        vm.prank(initialOwner);
        cosigner.transferOwnership(address(0));
        assertEq(cosigner.pendingOwner(), address(0));
        assertEq(cosigner.owner(), initialOwner);
    }

    function testFuzz_rawSignatureValidation_correct_owner(bytes32 hash) public view {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(initialOwnerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(wrapper.validateSignature(hash, signature));
    }

    function testFuzz_rawSignatureValidation_wrong_signer(bytes32 hash, uint256 wrongPK) public view {
        // Bound wrongPK to valid secp256k1 curve order range and ensure it's not the owner's key
        // secp256k1 curve order: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
        wrongPK = bound(wrongPK, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140);
        vm.assume(wrongPK != initialOwnerPK);
        vm.assume(vm.addr(wrongPK) != initialOwner);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function test_event_OwnershipTransferStarted() public {
        vm.expectEmit(true, true, false, false);
        emit Ownable2Step.OwnershipTransferStarted(initialOwner, newOwner);

        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);
    }

    function test_event_OwnershipTransferred() public {
        vm.prank(initialOwner);
        cosigner.transferOwnership(newOwner);

        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnershipTransferred(initialOwner, newOwner);

        vm.prank(newOwner);
        cosigner.acceptOwnership();
    }
}

/// @dev Wrapper to expose internal _rawSignatureValidation for testing
contract CosignerWrapper is Cosigner {
    constructor(address initialOwner) Cosigner(initialOwner) {}

    function validateSignature(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return _rawSignatureValidation(hash, signature);
    }
}
