// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";

import { ISuperformRewardsDistributor } from "interfaces/ISuperformRewardsDistributor.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title RewardsClaimSuperform
/// @notice Handles claiming, swapping, and donating rewards back to the MetaVault
contract RewardsClaimSuperform is ModuleBase {
    struct SwapData {
        address target;
        bytes data;
    }

    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when swap fails or is invalid
    error SwapFailedSuperform();

    /// @notice Thrown when swaps don't fulfill the promised amount
    error InsufficientSwapOutputSuperform();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emmitted when Superform rewards are claimed
    event RewardsClaimedSuperform(uint256 periodId, address[] rewardTokens, uint256[] amounts);

    /// @notice Emmitted when rewards are swapped
    event RewardsSwappedSuperform(address[] rewardTokens, uint256[] swappedAmounts);

    /// @notice Emmitted when swapped rewards are donated to the vault
    event RewardsDonatedSuperform(uint256 donatedAmount);

    /// @notice Claims rewards for a specific period
    /// @param periodId The period to claim rewards for
    /// @param rewardTokens Array of reward token addresses
    /// @param amountsClaimed Array of amounts to claim for each token
    /// @param proof Merkle proof for the claim
    /// @param swapDatas Array of swap calldata for each reward token
    /// @param minAmountsOut Minimum amounts expected from swaps
    function claimRewardsSuperform(
        ISuperformRewardsDistributor rewardsDistributor,
        uint256 periodId,
        address[] calldata rewardTokens,
        uint256[] calldata amountsClaimed,
        bytes32[] calldata proof,
        SwapData[] calldata swapDatas,
        uint256[] calldata minAmountsOut
    )
        external
        onlyRoles(MANAGER_ROLE)
    {
        // Claim the rewards
        rewardsDistributor.claim(address(this), periodId, rewardTokens, amountsClaimed, proof);

        emit RewardsClaimedSuperform(periodId, rewardTokens, amountsClaimed);

        // Swap and donate claimed rewards
        _swapAndDonateSuperform(rewardTokens, amountsClaimed, swapDatas, minAmountsOut);
    }

    /// @notice Batch claims rewards for multiple periods
    /// @param periodIds Array of period IDs to claim
    /// @param rewardTokens 2D array of reward token addresses
    /// @param amountsClaimed 2D array of amounts to claim for each token in each period
    /// @param proofs 2D array of Merkle proofs
    /// @param swapDatas 2D array of swap calldatas
    /// @param minAmountsOut 2D array of minimum amounts expected from swaps
    function batchClaimRewardsSuperform(
        ISuperformRewardsDistributor rewardsDistributor,
        uint256[] calldata periodIds,
        address[][] calldata rewardTokens,
        uint256[][] calldata amountsClaimed,
        bytes32[][] calldata proofs,
        SwapData[][] calldata swapDatas,
        uint256[][] calldata minAmountsOut
    )
        external
        onlyRoles(MANAGER_ROLE)
    {
        // Batch claim rewards
        rewardsDistributor.batchClaim(address(this), periodIds, rewardTokens, amountsClaimed, proofs);

        // Process each period's rewards
        for (uint256 i = 0; i < periodIds.length; i++) {
            emit RewardsClaimedSuperform(periodIds[i], rewardTokens[i], amountsClaimed[i]);
            _swapAndDonateSuperform(rewardTokens[i], amountsClaimed[i], swapDatas[i], minAmountsOut[i]);
        }
    }

    /// @notice Internal function to swap rewards to vault's asset and donate
    /// @param rewardTokens Tokens to swap
    /// @param amounts Amounts of tokens to swap
    /// @param swapDatas Swap calldata for each token
    /// @param minAmountsOut Minimum expected amounts from swaps
    function _swapAndDonateSuperform(
        address[] memory rewardTokens,
        uint256[] memory amounts,
        SwapData[] calldata swapDatas,
        uint256[] memory minAmountsOut
    )
        internal
    {
        uint256 totalDonated;
        address vaultAsset = asset();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            // Skip if reward token is already the vault asset
            if (rewardTokens[i] == vaultAsset) {
                totalDonated += amounts[i];
                vaultAsset.safeTransfer(address(this), amounts[i]);
                continue;
            }

            // Get initial asset balance before swap
            uint256 initialAssetBalance = vaultAsset.balanceOf(address(this));

            // Approve swap spender (assume first 20 bytes of swapData is the spender address)
            rewardTokens[i].safeApprove(swapDatas[i].target, amounts[i]);

            // Perform the swap
            (bool success,) = address(swapDatas[i].target).call(swapDatas[i].data);

            if (!success) {
                revert SwapFailedSuperform();
            }

            rewardTokens[i].safeApprove(swapDatas[i].target, 0);

            // Check new asset balance
            uint256 newAssetBalance = vaultAsset.balanceOf(address(this));
            uint256 swappedAmount = newAssetBalance - initialAssetBalance;

            // Verify minimum amount out
            if (swappedAmount < minAmountsOut[i]) {
                revert InsufficientSwapOutputSuperform();
            }

            totalDonated += swappedAmount;
        }

        // Donate if any rewards were processed
        if (totalDonated > 0) {
            emit RewardsDonatedSuperform(totalDonated);
            _totalIdle += totalDonated.toUint128();
        }
    }

    /// @notice Returns the function selectors for this module
    /// @return Array of function selectors
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](2);
        s[0] = this.claimRewardsSuperform.selector;
        s[1] = this.batchClaimRewardsSuperform.selector;
        return s;
    }
}
