// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTest} from "test/base/BaseTest.sol";
import {Cosigner} from "src/ops/Cosigner.sol";
import {CosignatureLib} from "src/lib/CosignatureLib.sol";
import {OrderLib} from "src/lib/OrderLib.sol";
import {CosignedOrder} from "src/Structs.sol";
import {IEIP712} from "src/interface/IEIP712.sol";
import {MockCommitteeSync} from "test/mocks/MockCommitteeSync.sol";

/// @title CosignerIntegrationTest
/// @notice Integration tests for CommitteeSync-backed Cosigner behavior with CosignatureLib
contract CosignerIntegrationTest is BaseTest {
    Cosigner public cosignerContract;
    MockCommitteeSync public committee;
    address public approvedSigner;
    uint256 public approvedSignerPK;

    function setUp() public override {
        super.setUp();
        vm.warp(1 days);

        committee = new MockCommitteeSync();
        cosignerContract = new Cosigner(address(committee), address(this));
        (approvedSigner, approvedSignerPK) = makeAddrAndKey("approvedSigner");

        uint256 signerExpires = block.timestamp + 365 days;
        committee.setConfig(cosignerContract.KEY(), approvedSigner, abi.encode(signerExpires));
    }

    function cosignWithContract(CosignedOrder memory co, address cosignerAddr, uint256 pk)
        internal
        view
        returns (CosignedOrder memory)
    {
        co.current.timestamp = block.timestamp;
        co.current.chainid = block.chainid;
        co.current.reactor = co.order.reactor;
        co.current.cosigner = cosignerAddr;
        co.current.input.token = co.order.input.token;
        co.current.input.value = cosignInValue;
        co.current.input.decimals = _tokenDecimals(co.order.input.token);
        co.current.output.token = co.order.output.token;
        co.current.output.value = cosignOutValue;
        co.current.output.decimals = _tokenDecimals(co.order.output.token);

        bytes32 digest = IEIP712(repermit).hashTypedData(OrderLib.hash(co.current));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory signature = bytes.concat(r, s, bytes1(v));
        co.trigger = co.current;
        co.currentCosignature = signature;
        co.triggerCosignature = signature;
        return co;
    }

    function test_integration_cosigner_contract_validates_with_CosignatureLib() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        triggerUpper = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        CosignedOrder memory co = order();
        co = cosignWithContract(co, address(cosignerContract), approvedSignerPK);

        CosignatureLib.validate(co, address(cosignerContract), repermit);
    }

    function test_integration_erc1271_returns_magic_value_for_valid_signature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(approvedSignerPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function test_integration_erc1271_reverts_for_unapproved_signature() public {
        (, uint256 unapprovedPK) = makeAddrAndKey("unapproved");

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unapprovedPK, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosignerContract.isValidSignature(hash, signature);
    }

    function test_integration_signer_expires_after_deadline() public {
        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        triggerUpper = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        (address tempSigner, uint256 tempSignerPK) = makeAddrAndKey("tempSigner");
        uint256 signerExpires = block.timestamp + 1 hours;
        committee.setConfig(cosignerContract.KEY(), tempSigner, abi.encode(signerExpires));

        CosignedOrder memory co = order();
        co = cosignWithContract(co, address(cosignerContract), tempSignerPK);
        CosignatureLib.validate(co, address(cosignerContract), repermit);

        vm.warp(block.timestamp + 1 hours + 1);

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

        bytes4 result = cosignerContract.isValidSignature(hash, signature);
        assertEq(result, bytes4(keccak256("isValidSignature(bytes32,bytes)")));

        committee.clearConfig(cosignerContract.KEY(), approvedSigner);

        vm.expectRevert(Cosigner.InvalidCosignature.selector);
        cosignerContract.isValidSignature(hash, signature);
    }

    function test_integration_multiple_cosigner_contracts_independent() public {
        MockCommitteeSync committee2 = new MockCommitteeSync();
        (address signer2, uint256 signer2PK) = makeAddrAndKey("signer2");
        Cosigner cosigner2 = new Cosigner(address(committee2), address(this));
        committee2.setConfig(cosigner2.KEY(), signer2, abi.encode(block.timestamp + 365 days));

        freshness = 300;
        inMax = 2_000;
        outAmount = 500;
        triggerUpper = 5_000;
        cosignInValue = 100;
        cosignOutValue = 200;

        CosignedOrder memory co1 = order();
        co1 = cosignWithContract(co1, address(cosignerContract), approvedSignerPK);
        CosignatureLib.validate(co1, address(cosignerContract), repermit);

        CosignedOrder memory co2 = order();
        co2 = cosignWithContract(co2, address(cosigner2), signer2PK);
        CosignatureLib.validate(co2, address(cosigner2), repermit);

        assertEq(address(cosignerContract.committee()), address(committee));
        assertEq(address(cosigner2.committee()), address(committee2));
        assertTrue(cosignerContract.isApprovedNow(approvedSigner));
        assertTrue(cosigner2.isApprovedNow(signer2));
    }
}
