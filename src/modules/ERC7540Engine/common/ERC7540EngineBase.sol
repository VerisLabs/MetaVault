// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { VaultData, VaultLib } from "types/Lib.sol";

/// @title ERC7540EngineBase
/// @notice Base contract for ERC7540 engine that manages multi-vault deposits and withdrawals across chains
/// @dev Extends ModuleBase to provide core functionality for processing redemption requests and managing vault state
contract ERC7540EngineBase is ModuleBase {
    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PRIVATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Internal cache struct to allocate in memory
    struct ProcessRedeemRequestCache {
        // List of vauts to withdraw from on each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] dstVaults;
        // List of shares to redeem on each vault in each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] sharesPerVault;
        // List of assets to withdraw on each vault in each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] assetsPerVault;
        // Cache length of list of each chain
        uint256[N_CHAINS] lens;
        // Assets to divest from other vaults
        uint256 amountToWithdraw;
        // Shares actually used
        uint256 sharesFulfilled;
        // Save assets that were withdrawn instantly
        uint256 totalClaimableWithdraw;
        // Cache totalAssets
        uint256 totalAssets;
        // Cache totalIdle
        uint256 totalIdle;
        // Cache totalDebt
        uint256 totalDebt;
        // Convert shares to assets at current price
        uint256 assets;
        // Cache shares to redeem
        uint256 shares;
        // Useful cache value for multichain withdrawals
        uint256 lastIndex;
        // Whether is a single or multivault withdrawal
        bool isSingleChain;
        bool isMultiChain;
        // Whether is a single or multivault withdrawal
        bool isMultiVault;
    }

    /// @dev Precomputes the withdrawal route following the order of the withdrawal queue
    /// according to the needed assets
    /// @param cache the memory pointer of the cache
    /// @dev writes the route to the cache struct
    ///
    /// Note: First it will try to fulfill the request with idle assets, after that it will
    /// loop through the withdrawal queue and compute the destination chains and vaults on each
    /// destionation chain, plus the shaes to redeem on each vault
    function _prepareWithdrawalRoute(ProcessRedeemRequestCache memory cache, bool despiseDust) internal view {
        // Use the local vaults first
        _exhaustWithdrawalQueue(cache, localWithdrawalQueue, false, false);
        // Use the crosschain vaults after
        _exhaustWithdrawalQueue(cache, xChainWithdrawalQueue, true, despiseDust);
    }

    /// @notice Internal function to process a withdrawal queue and determine optimal withdrawal routes
    /// @dev Iterates through a withdrawal queue to calculate how to fulfill a withdrawal request across multiple vaults
    /// and chains.
    /// The function:
    /// 1. Processes vaults in queue order until request is fulfilled
    /// 2. Calculates shares to withdraw from each vault
    /// 3. Updates debt tracking
    /// 4. Determines if withdrawal is single/multi chain and single/multi vault
    /// 5. Maintains withdrawal state in the cache structure
    ///
    /// For each vault in the queue:
    /// - Checks maximum withdrawable amount
    /// - Calculates required shares
    /// - Updates chain-specific withdrawal arrays
    /// - Tracks debt reductions
    /// - Updates withdrawal type flags (single/multi chain/vault)
    ///
    /// @param cache Storage structure containing withdrawal state and routing information:
    ///        - dstVaults: Arrays of vault IDs per chain
    ///        - sharesPerVault: Shares to withdraw per vault per chain
    ///        - assetsPerVault: Assets to withdraw per vault per chain
    ///        - lens: Number of vaults to process per chain
    ///        - amountToWithdraw: Remaining assets to withdraw
    ///        - totalDebt: Running total of vault debt
    ///        - isSingleChain/isMultiChain/isMultiVault: Withdrawal type flags
    /// @param queue The withdrawal queue to process (either local or cross-chain)
    /// @param resetValues If true, resets amountToWithdraw when queue is exhausted
    function _exhaustWithdrawalQueue(
        ProcessRedeemRequestCache memory cache,
        uint256[WITHDRAWAL_QUEUE_SIZE] memory queue,
        bool resetValues,
        bool despiseDust
    )
        internal
        view
    {
        // Cache how many chains we need and how many vaults in each chain
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            // If we exhausted the queue stop
            if (queue[i] == 0) {
                if (resetValues) {
                    // reset values
                    cache.amountToWithdraw = cache.assets - cache.totalIdle;
                }
                break;
            }

            // If its crosschain and the dust threshold is reached stop
            if (resetValues && despiseDust && cache.amountToWithdraw < dustThreshold) {
                uint256 amountToWithdraw = cache.amountToWithdraw;
                cache.amountToWithdraw = 0;
                cache.assets -= amountToWithdraw;
                cache.shares -= convertToShares(amountToWithdraw);
                break;
            }

            // If its fulfilled stop
            if (cache.amountToWithdraw == 0) {
                break;
            }

            // Cache next vault from the withdrawal queue
            VaultData memory vault = vaults[queue[i]];
            // Calcualate the maxWithdraw of the vault
            uint256 maxWithdraw = vault.convertToAssets(_sharesBalance(vault), asset(), true);

            // Dont withdraw more than max
            uint256 withdrawAssets = Math.min(maxWithdraw, cache.amountToWithdraw);
            if (withdrawAssets == 0) continue;
            // Cache chain index
            uint256 chainIndex = chainIndexes[vault.chainId];
            // Cache chain length
            uint256 len = cache.lens[chainIndex];
            // Push the superformId to the last index of the array
            cache.dstVaults[chainIndex][len] = vault.superformId;

            uint256 shares;
            if (cache.amountToWithdraw >= maxWithdraw) {
                uint256 balance = _sharesBalance(vault);
                shares = balance;
            } else {
                shares = vault.convertToShares(withdrawAssets, asset(), true);
            }

            if (shares == 0) continue;
            // Push the shares to redeeem of that vault
            cache.sharesPerVault[chainIndex][len] = shares;
            // Push the assetse to withdraw of that vault
            cache.assetsPerVault[chainIndex][len] = withdrawAssets;
            // Reduce the total debt by no more than the debt of this vault
            uint256 debtReduction = Math.min(vault.totalDebt, withdrawAssets);
            // Reduce totalDebt
            cache.totalDebt -= debtReduction;
            // Reduce needed assets
            cache.amountToWithdraw -= withdrawAssets;

            // Cache whether withdrawal spans multiple chains
            if (vault.chainId != THIS_CHAIN_ID) {
                if (!cache.isSingleChain && !cache.isMultiChain) {
                    // First external chain encountered
                    cache.isSingleChain = true;
                } else if (cache.isSingleChain) {
                    // Find the first external chain ID
                    uint256 firstChainId;
                    for (uint256 j = 0; j < N_CHAINS; j++) {
                        if (cache.lens[j] > 0 && j != chainIndexes[THIS_CHAIN_ID]) {
                            firstChainId = j;
                            break;
                        }
                    }
                    // If this vault is from a different chain than the first one, it's multi-chain
                    if (chainIndex != firstChainId) {
                        cache.isSingleChain = false;
                        cache.isMultiChain = true;
                    }
                }

                // Check if there are multiple vaults in this chain
                if (cache.lens[chainIndex] >= 1) {
                    cache.isMultiVault = true;
                }
            }

            // Increase index for iteration
            unchecked {
                cache.lens[chainIndex]++;
            }
        }
    }

    /// @notice Sets the minimum amount of assets that can be withdrawn without incurring a penalty.
    /// @dev This function allows the admin to define a threshold for "dust" withdrawals, which are
    /// amounts considered too small to be efficiently processed. Setting this threshold helps in
    /// managing the overall efficiency of asset management.
    /// @param _dustThreshold The new dust threshold value to be set.
    function setDustThreshold(uint256 _dustThreshold) external onlyRoles(ADMIN_ROLE) {
        dustThreshold = _dustThreshold;
    }
}
