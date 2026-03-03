// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import {Cosigner} from "src/ops/Cosigner.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockCommitteeSync} from "test/mocks/MockCommitteeSync.sol";

contract CosignerTest is Test {
    Cosigner public cosigner;
    CosignerWrapper public wrapper;
    MockCommitteeSync public committee;
    address public signer1;
    uint256 public signer1PK;
    address public signer2;
    uint256 public signer2PK;

    uint256 private constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140;
    bytes private constant INVALID_SIGNATURE =
        hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public {
        committee = new MockCommitteeSync();
        cosigner = new Cosigner(address(committee), address(this));
        wrapper = new CosignerWrapper(address(committee), address(this));
        (signer1, signer1PK) = makeAddrAndKey("signer1");
        (signer2, signer2PK) = makeAddrAndKey("signer2");
    }

    function test_constructor_sets_committee() public view {
        assertEq(address(cosigner.committee()), address(committee));
    }

    function test_constructor_sets_owner() public view {
        assertEq(cosigner.owner(), address(this));
    }

    function test_constructor_reverts_when_committee_is_zero() public {
        vm.expectRevert(Cosigner.InvalidCommittee.selector);
        new Cosigner(address(0), address(this));
    }

    function test_constructor_reverts_when_owner_is_zero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Cosigner(address(committee), address(0));
    }

    function test_isApprovedNow_returns_true_for_owner() public view {
        assertTrue(cosigner.isApprovedNow(address(this)));
    }

    function test_isApprovedNow_returns_false_for_unapproved() public view {
        assertFalse(cosigner.isApprovedNow(signer1));
    }

    function test_isApprovedNow_returns_true_for_active_signer() public {
        uint256 expires = block.timestamp + 1 days;
        _setSignerConfig(signer1, expires);

        assertTrue(cosigner.isApprovedNow(signer1));
    }

    function test_isApprovedNow_returns_false_for_expired_signer() public {
        _setSignerConfig(signer1, block.timestamp);

        assertFalse(cosigner.isApprovedNow(signer1));
    }

    function test_isApprovedNow_returns_false_for_malformed_config_bytes() public {
        committee.setConfig(cosigner.KEY(), signer1, hex"01");

        assertFalse(cosigner.isApprovedNow(signer1));
    }

    function test_rawSignatureValidation_accepts_approved_signer_signature() public {
        uint256 expires = block.timestamp + 1 days;
        _setSignerConfig(signer1, expires);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(wrapper.validateSignature(hash, signature));
    }

    function test_rawSignatureValidation_rejects_unapproved_signer() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer2PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function test_rawSignatureValidation_rejects_expired_signer() public {
        uint256 signerExpires = block.timestamp + 1 hours;
        _setSignerConfig(signer1, signerExpires);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(wrapper.validateSignature(hash, signature));

        vm.warp(block.timestamp + 1 hours + 1);
        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function test_rawSignatureValidation_rejects_invalid_signature() public {
        bytes32 hash = keccak256("test message");

        vm.expectRevert();
        wrapper.validateSignature(hash, INVALID_SIGNATURE);
    }

    function test_rawSignatureValidation_accepts_owner_signature_without_committee_approval() public {
        CosignerWrapper ownerWrapper = new CosignerWrapper(address(committee), signer1);

        bytes32 hash = keccak256("owner signed message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(ownerWrapper.isApprovedNow(signer1));
        assertTrue(ownerWrapper.validateSignature(hash, signature));
    }

    function test_isApprovedNow_owner_transfer_updates_approval() public {
        assertTrue(cosigner.isApprovedNow(address(this)));
        assertFalse(cosigner.isApprovedNow(signer1));

        cosigner.transferOwnership(signer1);

        assertFalse(cosigner.isApprovedNow(address(this)));
        assertTrue(cosigner.isApprovedNow(signer1));
    }

    function test_isApprovedNow_renounced_owner_not_approved() public {
        cosigner.renounceOwnership();
        assertFalse(cosigner.isApprovedNow(address(0)));
    }

    function test_zeroAddressConfig_cannotBypassSignatureValidation() public {
        uint256 expires = block.timestamp + 1 days;
        _setSignerConfig(address(0), expires);

        assertTrue(wrapper.isApprovedNow(address(0)));

        bytes32 hash = keccak256("attempt zero signer");

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        wrapper.validateSignature(hash, INVALID_SIGNATURE);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function test_erc1271_returns_magic_value_for_valid_signature() public {
        uint256 expires = block.timestamp + 1 days;
        _setSignerConfig(signer1, expires);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosigner.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function test_erc1271_reverts_for_unapproved_signature() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer2PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosigner.isValidSignature(hash, signature);
    }

    function testFuzz_rawSignatureValidation_approved_signer(bytes32 hash) public {
        uint256 expires = block.timestamp + 1 days;
        _setSignerConfig(signer1, expires);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1PK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(wrapper.validateSignature(hash, signature));
    }

    function testFuzz_rawSignatureValidation_unapproved_signer(bytes32 hash, uint256 wrongPK) public view {
        wrongPK = bound(wrongPK, 1, SECP256K1_CURVE_ORDER);
        vm.assume(wrongPK != signer1PK);
        vm.assume(wrongPK != signer2PK);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(wrapper.validateSignature(hash, signature));
    }

    function _setSignerConfig(address signer, uint256 signerExpires) private {
        committee.setConfig(cosigner.KEY(), signer, abi.encode(signerExpires));
    }
}

contract CosignerWrapper is Cosigner {
    constructor(address committee, address owner) Cosigner(committee, owner) {}

    function validateSignature(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return _rawSignatureValidation(hash, signature);
    }
}
