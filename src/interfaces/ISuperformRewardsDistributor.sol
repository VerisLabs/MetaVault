// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface ISuperformRewardsDistributor {
    function claim(
        address receiver_,
        uint256 periodId_,
        address[] calldata rewardTokens_,
        uint256[] calldata amountsClaimed_,
        bytes32[] calldata proof_
    )
        external;

    function batchClaim(
        address receiver_,
        uint256[] calldata periodIds_,
        address[][] calldata rewardTokens_,
        uint256[][] calldata amountsClaimed_,
        bytes32[][] calldata proofs_
    )
        external;

    function verifyClaim(
        address claimer_,
        uint256 periodId_,
        address[] calldata rewardTokens_,
        uint256[] calldata amountsClaimed_,
        bytes32[] calldata proof_
    )
        external
        view
        returns (bool valid);
}
