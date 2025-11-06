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

    function setUp() public override {
        super.setUp();
        vm.warp(1 days);
        // Deploy Cosigner contract with signer as the initial owner
        cosignerContract = new Cosigner(signer);
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

        // Create and sign order
        CosignedOrder memory co = order();
        co = cosignWithContract(co, address(cosignerContract), signerPK);

        // Validate using CosignatureLib with the Cosigner contract address
        CosignatureLib.validate(co, address(cosignerContract), repermit);
    }

    function test_integration_erc1271_returns_magic_value_for_valid_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e)); // ERC-1271 magic value
    }

    function test_integration_erc1271_returns_invalid_for_wrong_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Flip a bit to make signature invalid
        signature[0] = bytes1(uint8(signature[0]) ^ 0x01);

        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff)); // Invalid signature
    }

    function test_integration_cosigner_contract_validates_after_ownership_transfer() public {
        // Setup order parameters
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        // Create new owner
        (address newOwner, uint256 newOwnerPK) = makeAddrAndKey("newOwner");

        // Transfer ownership
        vm.prank(signer);
        cosignerContract.transferOwnership(newOwner);

        vm.prank(newOwner);
        cosignerContract.acceptOwnership();

        // Verify owner changed
        assertEq(cosignerContract.owner(), newOwner);

        // Create new order and sign with new owner
        CosignedOrder memory co = order();

        // Sign with new owner's key
        co = cosignWithContract(co, address(cosignerContract), newOwnerPK);

        // Should validate successfully with new owner
        CosignatureLib.validate(co, address(cosignerContract), repermit);
    }

    function test_integration_erc1271_with_old_owner_after_transfer() public {
        // Create signature with current owner
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, hash);
        bytes memory oldOwnerSig = abi.encodePacked(r, s, v);

        // Verify signature is valid before transfer
        bytes4 result = cosignerContract.isValidSignature(hash, oldOwnerSig);
        assertEq(result, bytes4(0x1626ba7e));

        // Transfer ownership
        (address newOwner,) = makeAddrAndKey("newOwner");

        vm.prank(signer);
        cosignerContract.transferOwnership(newOwner);

        vm.prank(newOwner);
        cosignerContract.acceptOwnership();

        // Old owner's signature should now be invalid
        result = cosignerContract.isValidSignature(hash, oldOwnerSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_integration_cosigner_contract_signer_function_returns_owner() public view {
        assertEq(cosignerContract.signer(), signer);
        assertEq(cosignerContract.owner(), signer);
    }

    function test_integration_multiple_cosigner_contracts_independent() public {
        // Deploy a second cosigner with a different owner
        (address owner2, uint256 owner2PK) = makeAddrAndKey("owner2");
        Cosigner cosigner2 = new Cosigner(owner2);

        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        outMax = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        // Create order signed by original signer
        CosignedOrder memory co1 = order();
        co1 = cosignWithContract(co1, address(cosignerContract), signerPK);

        // Should validate with cosignerContract
        CosignatureLib.validate(co1, address(cosignerContract), repermit);

        // Create order for cosigner2
        CosignedOrder memory co2 = order();

        // Sign with owner2's key
        co2 = cosignWithContract(co2, address(cosigner2), owner2PK);

        // Should validate with cosigner2
        CosignatureLib.validate(co2, address(cosigner2), repermit);

        // Verify both cosigners have different owners
        assertEq(cosignerContract.owner(), signer);
        assertEq(cosigner2.owner(), owner2);
        assertTrue(cosignerContract.owner() != cosigner2.owner());
    }
}
