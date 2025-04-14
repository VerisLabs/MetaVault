// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultWithdraw
} from "src/types/Lib.sol";

contract MockSignerRelayer is Test {
    uint256 private _prk;
    address public signerAddress;

    constructor(uint256 privateKey) {
        _prk = privateKey;
        signerAddress = vm.addr(privateKey);
    }

    struct SignatureParams {
        address controller;
        SingleXChainSingleVaultWithdraw sXsV;
        SingleXChainMultiVaultWithdraw sXmV;
        MultiXChainSingleVaultWithdraw mXsV;
        MultiXChainMultiVaultWithdraw mXmV;
        uint256 nonce;
        uint256 deadline;
    }

    function sign(SignatureParams memory params) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = keccak256(
            abi.encode(
                params.controller,
                keccak256(abi.encode(params.sXsV)),
                keccak256(abi.encode(params.sXmV)),
                keccak256(abi.encode(params.mXsV)),
                keccak256(abi.encode(params.mXmV)),
                params.nonce,
                params.deadline
            )
        );

        (v, r, s) = vm.sign(_prk, hash);
    }
}
