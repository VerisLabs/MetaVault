// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC7540EngineBase } from "./common/ERC7540EngineBase.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

import {
    LiqRequest,
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultData,
    VaultLib
} from "types/Lib.sol";

/// @title ERC7540EngineReader
/// @notice This module is used to read the state of the ERC7540Engine and to preview the withdrawal route
contract ERC7540EngineReader is ERC7540EngineBase {
    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @notice Simulates a withdrawal route to help relayers determine how to fulfill redemption requests
    /// @dev This is an off-chain helper function that calculates the optimal route for processing
    /// withdrawals across different chains and vaults. It computes:
    /// 1. How much can be fulfilled directly from idle assets
    /// 2. Which vaults need to be accessed for the remaining amount
    /// 3. The distribution of withdrawals across different chains and vaults
    /// The function follows the same withdrawal queue priority as actual withdrawals:
    /// - First uses idle assets
    /// - Then local chain vaults
    /// - Finally cross-chain vaults
    /// @param controller Address of shares owner
    /// @return cachedRoute A struct containing:
    ///         - The withdrawal route across different chains
    ///         - The shares to be redeemed from each vault
    ///         - The assets expected from each withdrawal
    ///         - The amount that can be fulfilled immediately from idle assets
    ///         - Various cached state values needed for processing
    function previewWithdrawalRoute(
        address controller,
        uint256 shares,
        bool despiseDust
    )
        public
        view
        returns (ProcessRedeemRequestCache memory cachedRoute)
    {
        if (shares == 0) {
            shares = pendingRedeemRequest(controller);
        }

        cachedRoute.shares = shares;
        cachedRoute.assets = convertToAssets(shares);
        cachedRoute.totalIdle = _totalIdle;
        cachedRoute.totalDebt = _totalDebt;
        cachedRoute.totalAssets = totalAssets();

        // Cannot process more assets than the available
        if (cachedRoute.assets > totalWithdrawableAssets()) {
            revert InsufficientAvailableAssets();
        }

        // If totalIdle can covers the amount fulfill directly
        if (cachedRoute.totalIdle >= cachedRoute.assets) {
            cachedRoute.sharesFulfilled = shares;
            cachedRoute.totalClaimableWithdraw = cachedRoute.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            // Cache amount to withdraw before reducing totalIdle
            cachedRoute.amountToWithdraw = cachedRoute.assets - cachedRoute.totalIdle;
            // Use totalIdle to fulfill the request
            if (cachedRoute.totalIdle > 0) {
                cachedRoute.totalClaimableWithdraw = cachedRoute.totalIdle;
                cachedRoute.sharesFulfilled = _convertToShares(cachedRoute.totalIdle, cachedRoute.totalAssets);
            }
            ///////////////////////////////// PREVIOUS CALCULATIONS ////////////////////////////////
            _prepareWithdrawalRoute(cachedRoute, despiseDust);
        }
        return cachedRoute;
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](1);
        s[0] = this.previewWithdrawalRoute.selector;
        return s;
    }
}
