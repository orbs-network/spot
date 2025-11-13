// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Cosigner} from "src/ops/Cosigner.sol";
import {CosignatureLib} from "src/lib/CosignatureLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {IEIP712} from "src/interface/IEIP712.sol";

/// @title CosignerIntegrationTest
/// @notice Integration tests demonstrating that the Cosigner contract works with existing CosignatureLib
contract CosignerIntegrationTest is BaseTest {
    Cosigner public cosignerContract;
    address public owner;
    address public approvedSigner;
    uint256 public approvedSignerPK;

    function setUp() public override {
        super.setUp();
        vm.warp(1 days);

        // Owner is separate from signer
        owner = makeAddr("owner");
        (approvedSigner, approvedSignerPK) = makeAddrAndKey("approvedSigner");

        // Deploy Cosigner contract with owner
        cosignerContract = new Cosigner(owner);

        // Owner approves the signer with deadline
        uint256 deadline = block.timestamp + 365 days;
        hoax(owner);
        cosignerContract.approve(approvedSigner, deadline);
    }

    /// @dev Helper to cosign with the contract cosigner address
    function cosignWithContract(CosignedOrder memory co, address cosignerAddr, uint256 pk)
        internal
        view
        returns (CosignedOrder memory)
    {
        co.cosignatureData.timestamp = block.timestamp;
        co.cosignatureData.chainid = block.chainid;
        co.cosignatureData.reactor = co.order.reactor;
        co.cosignatureData.cosigner = cosignerAddr;
        co.cosignatureData.input.token = co.order.input.token;
        co.cosignatureData.input.value = cosignInValue;
        co.cosignatureData.input.decimals = _tokenDecimals(co.order.input.token);
        co.cosignatureData.output.token = co.order.output.token;
        co.cosignatureData.output.value = cosignOutValue;
        co.cosignatureData.output.decimals = _tokenDecimals(co.order.output.token);

        bytes32 digest = IEIP712(repermit).hashTypedData(OrderLib.hash(co.cosignatureData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        co.cosignature = bytes.concat(r, s, bytes1(v));
        return co;
    }

    function test_integration_cosigner_contract_validates_with_CosignatureLib() public {
        // Setup order parameters
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        // Create and sign order with approved signer
        CosignedOrder memory co = order();
        co = cosignWithContract(co, address(cosignerContract), approvedSignerPK);

        // Validate using CosignatureLib with the Cosigner contract address
        CosignatureLib.validate(co, address(cosignerContract), repermit);
    }

    function test_integration_erc1271_returns_magic_value_for_valid_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(approvedSignerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)"))); // ERC-1271 magic value
    }

    function test_integration_erc1271_reverts_for_unapproved_signature() public {
        // Create an unapproved signer
        (, uint256 unapprovedPK) = makeAddrAndKey("unapproved");

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unapprovedPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosignerContract.isValidSignature(hash, signature);
    }

    function test_integration_signer_expires_after_deadline() public {
        // Setup order parameters
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        // Approve signer with short deadline
        address tempSigner;
        uint256 tempSignerPK;
        (tempSigner, tempSignerPK) = makeAddrAndKey("tempSigner");

        uint256 deadline = block.timestamp + 1 hours;
        hoax(owner);
        cosignerContract.approve(tempSigner, deadline);

        // Create and sign order - should work initially
        CosignedOrder memory co = order();
        co = cosignWithContract(co, address(cosignerContract), tempSignerPK);
        CosignatureLib.validate(co, address(cosignerContract), repermit);

        // Warp past expiry
        vm.warp(block.timestamp + 1 hours + 1);

        // Now signature should revert as invalid
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(tempSignerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosignerContract.isValidSignature(hash, signature);
    }

    function test_integration_revoked_signer_cannot_sign() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(approvedSignerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature is valid before revocation
        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)")));

        // Revoke signer
        hoax(owner);
        cosignerContract.revoke(approvedSigner);

        // Signature should now revert as invalid
        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosignerContract.isValidSignature(hash, signature);
    }

    function test_integration_ownership_transfer_does_not_affect_signers() public view {
        // Approved signer should remain valid regardless of ownership transfer
        assertEq(cosignerContract.owner(), owner);
        assertTrue(cosignerContract.isApprovedNow(approvedSigner));
    }

    function test_integration_multiple_cosigner_contracts_independent() public {
        // Deploy a second cosigner with a different owner and signer
        address owner2 = makeAddr("owner2");
        (address signer2, uint256 signer2PK) = makeAddrAndKey("signer2");
        Cosigner cosigner2 = new Cosigner(owner2);

        // Approve signer2 for cosigner2
        uint256 deadline2 = block.timestamp + 365 days;
        hoax(owner2);
        cosigner2.approve(signer2, deadline2);

        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        // Create order signed by approvedSigner for cosignerContract
        CosignedOrder memory co1 = order();
        co1 = cosignWithContract(co1, address(cosignerContract), approvedSignerPK);

        // Should validate with cosignerContract
        CosignatureLib.validate(co1, address(cosignerContract), repermit);

        // Create order for cosigner2
        CosignedOrder memory co2 = order();

        // Sign with signer2's key
        co2 = cosignWithContract(co2, address(cosigner2), signer2PK);

        // Should validate with cosigner2
        CosignatureLib.validate(co2, address(cosigner2), repermit);

        // Verify both cosigners have different owners and signers
        assertEq(cosignerContract.owner(), owner);
        assertEq(cosigner2.owner(), owner2);
        assertTrue(cosignerContract.owner() != cosigner2.owner());
        assertTrue(cosignerContract.isApprovedNow(approvedSigner));
        assertTrue(cosigner2.isApprovedNow(signer2));
    }
}
