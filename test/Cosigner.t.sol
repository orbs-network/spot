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
    address public owner;
    uint256 public ownerPK;
    address public signer1;
    uint256 public signer1PK;
    address public signer2;
    uint256 public signer2PK;
    address public unauthorized;

    // secp256k1 curve order - maximum valid private key
    uint256 private constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140;
    // Invalid signature - all zeros
    bytes private constant INVALID_SIGNATURE =
        hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public {
        (owner, ownerPK) = makeAddrAndKey("owner");
        (signer1, signer1PK) = makeAddrAndKey("signer1");
        (signer2, signer2PK) = makeAddrAndKey("signer2");
        unauthorized = makeAddr("unauthorized");

        cosigner = new Cosigner(owner);
        wrapper = new CosignerWrapper(owner);
    }

    function test_constructor_sets_initial_owner() public view {
        assertEq(cosigner.owner(), owner);
    }

    function test_approveSigner_adds_signer_with_ttl() public {
        uint256 ttl = 1 days;
        uint256 expectedExpiry = block.timestamp + ttl;

        vm.expectEmit(true, false, false, true);
        emit Cosigner.SignerApproved(signer1, expectedExpiry);

        vm.prank(owner);
        cosigner.approveSigner(signer1, ttl);

        assertEq(cosigner.approvedSigners(signer1), expectedExpiry);
        assertTrue(cosigner.isSignerApproved(signer1));
    }

    function test_approveSigner_reverts_when_not_owner() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.approveSigner(signer1, 1 days);
    }

    function test_revokeSigner_removes_signer() public {
        vm.prank(owner);
        cosigner.approveSigner(signer1, 1 days);

        assertTrue(cosigner.isSignerApproved(signer1));

        vm.expectEmit(true, false, false, false);
        emit Cosigner.SignerRevoked(signer1);

        vm.prank(owner);
        cosigner.revokeSigner(signer1);

        assertEq(cosigner.approvedSigners(signer1), 0);
        assertFalse(cosigner.isSignerApproved(signer1));
    }

    function test_revokeSigner_reverts_when_not_owner() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.revokeSigner(signer1);
    }

    function test_isSignerApproved_returns_false_for_unapproved() public view {
        assertFalse(cosigner.isSignerApproved(signer1));
    }

    function test_isSignerApproved_returns_false_for_expired() public {
        vm.prank(owner);
        cosigner.approveSigner(signer1, 1 hours);

        assertTrue(cosigner.isSignerApproved(signer1));

        vm.warp(block.timestamp + 1 hours + 1);

        assertFalse(cosigner.isSignerApproved(signer1));
    }

    function test_rawSignatureValidation_accepts_approved_signer_signature() public {
        vm.prank(owner);
        wrapper.approveSigner(signer1, 1 days);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool valid = wrapper.validateSignature(hash, signature);
        assertTrue(valid);
    }

    function test_rawSignatureValidation_rejects_unapproved_signer() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer2PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool valid = wrapper.validateSignature(hash, signature);
        assertFalse(valid);
    }

    function test_rawSignatureValidation_rejects_expired_signer() public {
        vm.prank(owner);
        wrapper.approveSigner(signer1, 1 hours);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Valid before expiry
        bool valid = wrapper.validateSignature(hash, signature);
        assertTrue(valid);

        // Invalid after expiry
        vm.warp(block.timestamp + 1 hours + 1);
        valid = wrapper.validateSignature(hash, signature);
        assertFalse(valid);
    }

    function test_rawSignatureValidation_rejects_invalid_signature() public view {
        bytes32 hash = keccak256("test message");

        bool valid = wrapper.validateSignature(hash, INVALID_SIGNATURE);
        assertFalse(valid);
    }

    function test_transferOwnership_initiates_two_step_transfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        cosigner.transferOwnership(newOwner);

        // Owner should still be the initial owner
        assertEq(cosigner.owner(), owner);
        // Pending owner should be set
        assertEq(cosigner.pendingOwner(), newOwner);
    }

    function test_acceptOwnership_completes_transfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        cosigner.transferOwnership(newOwner);

        vm.prank(newOwner);
        cosigner.acceptOwnership();

        assertEq(cosigner.owner(), newOwner);
        assertEq(cosigner.pendingOwner(), address(0));
    }

    function test_transferOwnership_reverts_when_not_owner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.transferOwnership(newOwner);
    }

    function test_acceptOwnership_reverts_when_not_pending_owner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        cosigner.transferOwnership(newOwner);

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        cosigner.acceptOwnership();
    }

    function test_transferOwnership_to_zero_address_cancels_pending() public {
        address newOwner = makeAddr("newOwner");
        // First initiate transfer
        vm.prank(owner);
        cosigner.transferOwnership(newOwner);
        assertEq(cosigner.pendingOwner(), newOwner);

        // Then cancel by transferring to zero address
        vm.prank(owner);
        cosigner.transferOwnership(address(0));
        assertEq(cosigner.pendingOwner(), address(0));
        assertEq(cosigner.owner(), owner);
    }

    function test_erc1271_returns_magic_value_for_valid_signature() public {
        vm.prank(owner);
        cosigner.approveSigner(signer1, 1 days);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosigner.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function test_erc1271_returns_invalid_for_unapproved_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer2PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosigner.isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function testFuzz_rawSignatureValidation_approved_signer(bytes32 hash) public {
        vm.prank(owner);
        wrapper.approveSigner(signer1, 1 days);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(wrapper.validateSignature(hash, signature));
    }

    function testFuzz_rawSignatureValidation_unapproved_signer(bytes32 hash, uint256 wrongPK) public view {
        // Bound wrongPK to valid secp256k1 curve order range
        wrongPK = bound(wrongPK, 1, SECP256K1_CURVE_ORDER);
        vm.assume(wrongPK != signer1PK);
        vm.assume(wrongPK != signer2PK);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function test_event_OwnershipTransferStarted() public {
        address newOwner = makeAddr("newOwner");
        vm.expectEmit(true, true, false, false);
        emit Ownable2Step.OwnershipTransferStarted(owner, newOwner);

        vm.prank(owner);
        cosigner.transferOwnership(newOwner);
    }

    function test_event_OwnershipTransferred() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        cosigner.transferOwnership(newOwner);

        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnershipTransferred(owner, newOwner);

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
