// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Test } from "forge-std/Test.sol";
import { ISuperformRewardsDistributor } from "interfaces/Lib.sol";

contract MockRewardsDistributor is Test, ISuperformRewardsDistributor {
    bool public isValidSignature = true;

    function claim(
        address receiver_,
        uint256 periodId_,
        address[] calldata rewardTokens_,
        uint256[] calldata amountsClaimed_,
        bytes32[] calldata proof_
    )
        public
    {
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            deal(rewardTokens_[i], receiver_, amountsClaimed_[i]);
        }
    }

    function batchClaim(
        address receiver_,
        uint256[] calldata periodIds_,
        address[][] calldata rewardTokens_,
        uint256[][] calldata amountsClaimed_,
        bytes32[][] calldata proofs_
    )
        public
    {
        for (uint256 i; i < rewardTokens_.length; i++) {
            claim(receiver_, periodIds_[i], rewardTokens_[i], amountsClaimed_[i], proofs_[i]);
        }
    }

    function verifyClaim(
        address claimer_,
        uint256 periodId_,
        address[] calldata rewardTokens_,
        uint256[] calldata amountsClaimed_,
        bytes32[] calldata proof_
    )
        external
        view
        returns (bool)
    {
        return isValidSignature;
    }

    function setIsValidSignature(bool _isValid) public {
        isValidSignature = _isValid;
    }
}
