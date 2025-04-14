// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC7540EngineBase } from "./ERC7540EngineBase.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import {
    LiqRequest,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    SingleVaultSFData,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultWithdraw,
    VaultData
} from "types/Lib.sol";

/// @title ERC7540ProcessRedeemBase
/// @notice Shared implementation for ERC7540Engine and ERC7540EngineSignatures
/// @dev Contains the core implementation of process redeem request logic
abstract contract ERC7540ProcessRedeemBase is ERC7540EngineBase {
    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

    /// @notice Thrown when shares requested are greater than pending redeem request
    error ExcessiveSharesRequested();

    /// @notice Thrown when shares are already being processed crosschain
    error SharesInProcess();

    /// @notice Thrown when assets were not liquidated
    error AssetsNotLiquidated();

    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @param shares to redeem and burn
    /// @param controller controller that created the request
    struct ProcessRedeemRequestConfig {
        uint256 shares;
        address controller;
        SingleXChainSingleVaultWithdraw sXsV;
        SingleXChainMultiVaultWithdraw sXmV;
        MultiXChainSingleVaultWithdraw mXsV;
        MultiXChainMultiVaultWithdraw mXmV;
    }

    /// @notice Executes the redeem request for a controller
    /// @dev Processes a redemption request by withdrawing assets from vaults based on the withdrawal route
    /// @param config The configuration for the redemption request
    function _processRedeemRequest(ProcessRedeemRequestConfig memory config) internal {
        // Use struct to avoid stack too deep
        ProcessRedeemRequestCache memory cache;
        cache.totalIdle = _totalIdle;
        cache.totalDebt = _totalDebt;

        // Custom error check for shares greater than pending redeem request
        uint256 pendingShares = pendingRedeemRequest(config.controller);
        if (config.shares > pendingShares) revert ExcessiveSharesRequested();
        if (config.shares > pendingShares - pendingProcessedShares[config.controller]) revert SharesInProcess();

        cache.assets = convertToAssets(config.shares);
        cache.totalAssets = totalAssets();

        // Cannot process more assets than the
        if (cache.assets > totalWithdrawableAssets()) {
            revert InsufficientAvailableAssets();
        }

        // If totalIdle can covers the amount fulfill directly
        if (cache.totalIdle >= cache.assets) {
            cache.sharesFulfilled = config.shares;
            cache.totalClaimableWithdraw = cache.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            // Cache amount to withdraw before reducing totalIdle
            cache.amountToWithdraw = cache.assets - cache.totalIdle;
            // Use totalIdle to fulfill the request
            if (cache.totalIdle > 0) {
                cache.totalClaimableWithdraw = cache.totalIdle;
                cache.sharesFulfilled = _convertToShares(cache.totalIdle, cache.totalAssets);
            }

            _prepareWithdrawalRoute(cache, false);

            // Handle this chain withdrawals
            _processThisChainWithdrawals(config, cache);

            // Handle external chain withdrawals
            if (cache.isSingleChain) {
                _processSingleChainWithdrawals(config, cache);
            }

            if (cache.isMultiChain) {
                if (!cache.isMultiVault) {
                    _processMultiChainSingleVault(config, cache);
                } else {
                    _processMultiChainMultiVault(config, cache);
                }
            }
        }

        // Optimistically deduct all assets to withdraw from the total
        _totalIdle = cache.totalIdle.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();
        _totalDebt = cache.totalDebt.toUint128();

        // Check that totalAssets was actually reduced by the amount to withdraw
        if (totalAssets() > cache.totalAssets - cache.amountToWithdraw) {
            revert AssetsNotLiquidated();
        }

        emit ProcessRedeemRequest(config.controller, config.shares);

        pendingProcessedShares[config.controller] += config.shares - cache.sharesFulfilled;

        // Burn all shares from this contract(they already have been transferred)
        _burn(address(this), config.shares);
        // Fulfill request with instant withdrawals only
        _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, config.controller, true);
    }

    /// @dev Process withdrawals from vaults on the current chain
    /// @param config The configuration for the redemption request
    /// @param cache The cache structure for storing intermediate calculation results
    function _processThisChainWithdrawals(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
        if (cache.lens[chainIndex] == 0) return;

        if (cache.lens[chainIndex] == 1) {
            // Process single vault
            uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
            uint256 assetsAmount = cache.assetsPerVault[chainIndex][0];
            uint256 superformId = cache.dstVaults[chainIndex][0];

            uint256 withdrawn =
                _liquidateSingleDirectSingleVault(vaults[superformId].vaultAddress, sharesAmount, 0, address(this));

            cache.sharesFulfilled += _convertToShares(assetsAmount, cache.totalAssets);
            _reduceVaultDebt(superformId, assetsAmount);
            cache.totalClaimableWithdraw += withdrawn;
            cache.totalIdle += withdrawn;
        } else {
            // Process multi vault
            uint256 len = cache.lens[chainIndex];
            address[] memory vaultAddresses = new address[](len);
            uint256[] memory amounts = new uint256[](len);
            uint256 requestedAssets;

            for (uint256 i = 0; i < len;) {
                vaultAddresses[i] = vaults[cache.dstVaults[chainIndex][i]].vaultAddress;
                amounts[i] = cache.sharesPerVault[chainIndex][i];
                uint256 superformId = cache.dstVaults[chainIndex][i];
                requestedAssets += cache.assetsPerVault[chainIndex][i];
                _reduceVaultDebt(superformId, cache.assetsPerVault[chainIndex][i]);
                unchecked {
                    ++i;
                }
            }

            uint256 withdrawn = _liquidateSingleDirectMultiVault(
                vaultAddresses, amounts, _getEmptyuintArray(amounts.length), address(this)
            );

            cache.totalClaimableWithdraw += withdrawn;
            cache.sharesFulfilled += _convertToShares(requestedAssets, cache.totalAssets);
            cache.totalIdle += withdrawn;
        }
    }

    /// @dev Process withdrawals from vaults on a single external chain
    /// @param config The configuration for the redemption request
    /// @param cache The cache structure for storing intermediate calculation results
    function _processSingleChainWithdrawals(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        if (!cache.isMultiVault) {
            // Single chain, single vault
            uint256 superformId;
            uint256 amount;
            uint64 chainId;

            for (uint256 i = 0; i < N_CHAINS;) {
                if (DST_CHAINS[i] == THIS_CHAIN_ID) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (cache.lens[i] > 0) {
                    chainId = DST_CHAINS[i];
                    uint256 chainIndex = chainIndexes[chainId];
                    superformId = cache.dstVaults[i][0];
                    amount = cache.sharesPerVault[i][0];

                    _liquidateSingleXChainSingleVault(
                        chainId, superformId, amount, config.controller, config.sXsV, cache.assetsPerVault[i][0]
                    );

                    _reduceVaultDebt(superformId, cache.assetsPerVault[chainIndex][0]);
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            // Single chain, multi vault
            uint256[] memory superformIds;
            uint256[] memory amounts;
            uint64 chainId;

            for (uint256 i = 0; i < N_CHAINS;) {
                if (DST_CHAINS[i] == THIS_CHAIN_ID) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (cache.lens[i] > 0) {
                    chainId = DST_CHAINS[i];
                    superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);
                    amounts = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);
                    uint256 totalDebtReduction;

                    for (uint256 j = 0; j < superformIds.length;) {
                        _reduceVaultDebt(superformIds[j], cache.assetsPerVault[i][j]);
                        totalDebtReduction += cache.assetsPerVault[i][j];
                        unchecked {
                            ++j;
                        }
                    }

                    _liquidateSingleXChainMultiVault(
                        chainId,
                        superformIds,
                        amounts,
                        config.controller,
                        config.sXmV,
                        totalDebtReduction,
                        _toDynamicUint256Array(cache.assetsPerVault[i], cache.lens[i])
                    );
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @dev Process withdrawals from a single vault on multiple external chains
    /// @param config The configuration for the redemption request
    /// @param cache The cache structure for storing intermediate calculation results
    function _processMultiChainSingleVault(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainsLen;
        for (uint256 i = 0; i < cache.lens.length;) {
            if (cache.lens[i] > 0) chainsLen++;
            unchecked {
                ++i;
            }
        }

        uint8[][] memory ambIds = new uint8[][](chainsLen);
        uint64[] memory dstChainIds = new uint64[](chainsLen);
        SingleVaultSFData[] memory singleVaultDatas = new SingleVaultSFData[](chainsLen);
        uint256 lastChainsIndex;

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] > 0) {
                dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                ++lastChainsIndex;
            }
            unchecked {
                ++i;
            }
        }

        uint256[] memory totalDebtReductions = new uint256[](chainsLen);

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            totalDebtReductions[cache.lastIndex] = cache.assetsPerVault[i][0];
            singleVaultDatas[cache.lastIndex] = SingleVaultSFData({
                superformId: cache.dstVaults[i][0],
                amount: cache.sharesPerVault[i][0],
                outputAmount: config.mXsV.outputAmounts[cache.lastIndex],
                maxSlippage: config.mXsV.maxSlippages[cache.lastIndex],
                liqRequest: config.mXsV.liqRequests[cache.lastIndex],
                permit2data: "",
                hasDstSwap: config.mXsV.hasDstSwaps[cache.lastIndex],
                retain4626: false,
                receiverAddress: config.controller,
                receiverAddressSP: address(0),
                extraFormData: ""
            });

            ambIds[cache.lastIndex] = config.mXsV.ambIds[cache.lastIndex];
            _reduceVaultDebt(cache.dstVaults[i][0], cache.assetsPerVault[i][0]);
            cache.lastIndex++;
            unchecked {
                ++i;
            }
        }

        _liquidateMultiDstSingleVault(ambIds, dstChainIds, singleVaultDatas, config.mXsV.value, totalDebtReductions);
    }

    function _processMultiChainMultiVault(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainsLen;
        for (uint256 i = 0; i < cache.lens.length;) {
            if (cache.lens[i] > 0) chainsLen++;
            unchecked {
                ++i;
            }
        }

        uint8[][] memory ambIds = new uint8[][](chainsLen);
        uint64[] memory dstChainIds = new uint64[](chainsLen);
        MultiVaultSFData[] memory multiVaultDatas = new MultiVaultSFData[](chainsLen);
        uint256 lastChainsIndex;

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] > 0) {
                dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                ++lastChainsIndex;
            }
            unchecked {
                ++i;
            }
        }

        uint256[] memory totalDebtReductions = new uint256[](chainsLen);
        uint256[][] memory debtReductionsPerVault = new uint256[][](chainsLen);

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            bool[] memory emptyBoolArray = _getEmptyBoolArray(cache.lens[i]);
            uint256[] memory superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);

            multiVaultDatas[cache.lastIndex] = MultiVaultSFData({
                superformIds: superformIds,
                amounts: _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]),
                outputAmounts: config.mXmV.outputAmounts[cache.lastIndex],
                maxSlippages: config.mXmV.maxSlippages[cache.lastIndex],
                liqRequests: config.mXmV.liqRequests[cache.lastIndex],
                permit2data: "",
                hasDstSwaps: config.mXmV.hasDstSwaps[cache.lastIndex],
                retain4626s: emptyBoolArray,
                receiverAddress: config.controller,
                receiverAddressSP: address(0),
                extraFormData: ""
            });

            ambIds[cache.lastIndex] = config.mXmV.ambIds[cache.lastIndex];
            debtReductionsPerVault[cache.lastIndex] = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);

            for (uint256 j = 0; j < superformIds.length;) {
                _reduceVaultDebt(superformIds[j], cache.assetsPerVault[i][j]);
                totalDebtReductions[cache.lastIndex] += cache.assetsPerVault[i][j];
                unchecked {
                    ++j;
                }
            }

            cache.lastIndex++;
            unchecked {
                ++i;
            }
        }

        _liquidateMultiDstMultiVault(
            ambIds, dstChainIds, multiVaultDatas, config.mXmV.value, totalDebtReductions, debtReductionsPerVault
        );
    }

    function _reduceVaultDebt(uint256 superformId, uint256 amount) private {
        unchecked {
            vaults[superformId].totalDebt =
                (amount >= vaults[superformId].totalDebt ? 0 : vaults[superformId].totalDebt - amount).toUint128();
        }
    }

    /// @dev Withdraws assets from a single vault on the same chain
    /// @param vault Address of the vault to withdraw from
    /// @param amount Amount of shares to redeem
    /// @param minAmountOut Minimum amount of assets expected to receive
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Amount of assets actually withdrawn
    function _liquidateSingleDirectSingleVault(
        address vault,
        uint256 amount,
        uint256 minAmountOut,
        address receiver
    )
        private
        returns (uint256 withdrawn)
    {
        uint256 balanceBefore = asset().balanceOf(address(this));
        ERC4626(vault).redeem(amount, address(this), receiver);
        withdrawn = asset().balanceOf(address(this)) - balanceBefore;
        if (withdrawn < minAmountOut) {
            revert InsufficientAssets();
        }
    }

    /// @dev Withdraws assets from multiple vaults on the same chain
    /// @param vaults_ Array of vault addresses to withdraw from
    /// @param amounts Array of share amounts to redeem from each vault
    /// @param minAmountsOut Array of minimum amounts of assets expected from each vault
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Total amount of assets withdrawn from all vaults
    function _liquidateSingleDirectMultiVault(
        address[] memory vaults_,
        uint256[] memory amounts,
        uint256[] memory minAmountsOut,
        address receiver
    )
        private
        returns (uint256 withdrawn)
    {
        for (uint256 i = 0; i < vaults_.length;) {
            withdrawn += _liquidateSingleDirectSingleVault(vaults_[i], amounts[i], minAmountsOut[i], receiver);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    /// @param totalDebtReduction total debt reductions per chain
    function _liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalDebtReduction
    )
        private
    {
        gateway.liquidateSingleXChainSingleVault{ value: config.value }(
            chainId, superformId, amount, receiver, config, totalDebtReduction
        );
    }

    /// @dev Initiates withdrawals from multiple vaults on a single different chain
    /// @param chainId ID of the destination chain
    /// @param superformIds Array of superform IDs to withdraw from
    /// @param amounts Array of share amounts to withdraw from each superform
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawals
    /// @param totalDebtReduction Total debt reduction for this chain's vaults
    function _liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalDebtReduction,
        uint256[] memory debtReductionPerVault
    )
        private
    {
        gateway.liquidateSingleXChainMultiVault{ value: config.value }(
            chainId, superformIds, amounts, receiver, config, totalDebtReduction, debtReductionPerVault
        );
    }

    /// @dev Initiates withdrawals from a single vault on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param singleVaultDatas Array of SingleVaultSFData structures for each withdrawal
    /// @param value Amount of native tokens to send with the transaction
    /// @param totalDebtReductions Array of total debt reductions per destination chain
    function _liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256 value,
        uint256[] memory totalDebtReductions
    )
        private
    {
        gateway.liquidateMultiDstSingleVault{ value: value }(ambIds, dstChainIds, singleVaultDatas, totalDebtReductions);
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    /// @param value Amount of native tokens to send with the transaction
    /// @param totalDebtReduction Array of total debt reductions per chain
    /// @param debtReductionsPerVault Array of arrays detailing debt reductions per vault per chain
    function _liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256 value,
        uint256[] memory totalDebtReduction,
        uint256[][] memory debtReductionsPerVault
    )
        private
    {
        gateway.liquidateMultiDstMultiVault{ value: value }(
            ambIds, dstChainIds, multiVaultDatas, totalDebtReduction, debtReductionsPerVault
        );
    }
}
