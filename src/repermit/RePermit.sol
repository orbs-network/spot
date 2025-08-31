// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IEIP712} from "src/interface/IEIP712.sol";

import {RePermitLib} from "./RePermitLib.sol";

contract RePermit is EIP712, IEIP712 {
    using SafeERC20 for IERC20;

    error InvalidSignature();
    error Expired();
    error InsufficientAllowance();
    error Canceled();

    // signer => hash => spent
    mapping(address => mapping(bytes32 => uint256)) public spent;

    constructor() EIP712("RePermit", "1") {}

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTypedData(bytes32 structHash) public view returns (bytes32 digest) {
        return _hashTypedDataV4(structHash);
    }

    function cancel(bytes32[] calldata digests) external {
        for (uint256 i = 0; i < digests.length; i++) {
            spent[msg.sender][digests[i]] = type(uint256).max;
            emit RePermitLib.Cancel(msg.sender, digests[i]);
        }
    }

    function repermitWitnessTransferFrom(
        RePermitLib.RePermitTransferFrom memory permit,
        RePermitLib.TransferRequest calldata request,
        address signer,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        if (block.timestamp > permit.deadline) revert Expired();

        bytes32 hash = hashTypedData(RePermitLib.hashWithWitness(permit, witness, witnessTypeString, msg.sender));
        if (!SignatureChecker.isValidSignatureNow(signer, hash, signature)) revert InvalidSignature();

        if (spent[signer][hash] == type(uint256).max) revert Canceled();

        if (request.amount == 0) return;
        uint256 _spent = (spent[signer][hash] += request.amount); // increment and get
        if (_spent > permit.permitted.amount) revert InsufficientAllowance();

        IERC20(permit.permitted.token).safeTransferFrom(signer, request.to, request.amount);
        emit RePermitLib.Spend(signer, hash, permit.permitted.token, request.to, request.amount, _spent);
    }
}
