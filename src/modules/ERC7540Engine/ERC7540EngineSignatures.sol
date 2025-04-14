// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC7540ProcessRedeemBase } from "./common/ERC7540ProcessRedeemBase.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import { ProcessRedeemRequestParams } from "types/Lib.sol";

/// @title ERC7540EngineSignatures
/// @notice Implementation of a ERC4626 multi-vault deposit liquidity engine with cross-chain functionalities
/// @dev Extends ERC7540ProcessRedeemBase contract and implements advanced redeem request processing
contract ERC7540EngineSignatures is ERC7540ProcessRedeemBase {
    /// @notice Thrown when signature has expired
    error SignatureExpired();

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when nonce is invalid
    error InvalidNonce();

    /// @notice Verifies that a signature is valid for the given request parameters
    /// @param params The request parameters to verify
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param nonce The user's current nonce
    /// @param v The recovery byte of the signature
    /// @param r The r value of the signature
    /// @param s The s value of the signature
    function verifySignature(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        view
        returns (bool)
    {
        // Check deadline
        if (block.timestamp > deadline) {
            revert SignatureExpired();
        }

        // Check nonce
        if (nonce != nonces(params.controller)) {
            revert InvalidNonce();
        }

        // Hash the parameters including deadline and nonce
        bytes32 paramsHash = computeHash(params, deadline, nonce);

        // Verify signature using SignatureCheckerLib
        return SignatureCheckerLib.isValidSignatureNow(signerRelayer, paramsHash, abi.encodePacked(r, s, v));
    }

    /// @notice Computes the hash of the request parameters
    /// @param params The request parameters
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param nonce The user's current nonce
    /// @return The computed hash
    function computeHash(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                params.controller, params.shares, params.sXsV, params.sXmV, params.mXsV, params.mXmV, deadline, nonce
            )
        );
    }

    /// @notice Process a request with a valid relayer signature
    /// @param params The request parameters
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param v The recovery byte of the signature
    /// @param r The r value of the signature
    /// @param s The s value of the signature
    function processSignedRequest(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        address controller = params.controller;
        // Get and increment nonce
        uint256 nonce = nonces(controller);

        // Verify signature
        if (!verifySignature(params, deadline, nonce, v, r, s)) {
            revert InvalidSignature();
        }

        /// @solidity memory-safe-assembly
        assembly {
            // Compute the nonce slot and load its value
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, controller)
            let nonceSlot := keccak256(0x0c, 0x20)
            let nonceValue := sload(nonceSlot)
            // Increment and store the updated nonce
            sstore(nonceSlot, add(nonceValue, 1))
        }

        // Process the request
        _processRedeemRequest(
            ProcessRedeemRequestConfig(
                params.shares == 0 ? pendingRedeemRequest(params.controller) : params.shares,
                params.controller,
                params.sXsV,
                params.sXmV,
                params.mXsV,
                params.mXmV
            )
        );
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](3);
        s[0] = this.processSignedRequest.selector;
        s[1] = this.verifySignature.selector;
        s[2] = this.computeHash.selector;
        return s;
    }
}
