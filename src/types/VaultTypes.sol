// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { LiqRequest } from "./SuperformTypes.sol";
import { ISharePriceOracle, VaultReport } from "interfaces/ISharePriceOracle.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { IBaseRouter } from "src/interfaces/IBaseRouter.sol";

import { IHurdleRateOracle } from "src/interfaces/IHurdleRateOracle.sol";
import { ISuperPositions } from "src/interfaces/ISuperPositions.sol";
import { ISuperformFactory } from "src/interfaces/ISuperformFactory.sol";
import { ISuperformGateway } from "src/interfaces/ISuperformGateway.sol";

/// @dev The maximum allowable staleness for oracle data before being considered outdated
uint256 constant ORACLE_STALENESS_TOLERANCE = 1 days;

/// @notice A struct describing the status of an underlying vault
/// @dev Contains data about a vault's chain ID, share price, oracle, and more
struct VaultData {
    /// @dev The ID of the chain where the vault is deployed
    uint32 chainId;
    /// @dev The superform ID of the vault in the Superform protocol
    uint256 superformId;
    /// @dev The oracle that provides the share price for the vault
    ISharePriceOracle oracle;
    /// @dev The number of decimals used in the ERC4626 shares
    uint8 decimals;
    /// @dev The total assets invested in the vault
    uint128 totalDebt;
    /// @dev The address of the vault
    address vaultAddress;
}

/// @notice Configuration parameters for a vault
/// @dev Contains all the necessary settings and addresses for vault operation
struct VaultConfig {
    /// @dev The address of the underlying asset token
    address asset;
    /// @dev The name of the vault
    string name;
    /// @dev The symbol of the vault
    string symbol;
    /// @dev The management fee in basis points
    uint16 managementFee;
    /// @dev The performance fee in basis points
    uint16 performanceFee;
    /// @dev The oracle fee in basis points
    uint16 oracleFee;
    /// @dev The lock time for shares in seconds
    uint24 sharesLockTime;
    /// @dev The oracle contract for hurdle rates
    IHurdleRateOracle hurdleRateOracle;
    /// @dev The SuperPositions contract
    ISuperPositions superPositions;
    /// @dev The treasury address for fee collection
    address treasury;
    /// @dev The address of the signer relayer
    address signerRelayer;
    /// @dev The owner address of the vault
    address owner;
}

/// @notice A helper library to define methods for handling VaultData
/// @dev Provides methods to simulate conversions between shares and assets for a vault
library VaultLib {
    error StaleSharePrice();

    /// @notice Simulates the ERC4626 {convertToAssets} function using vault data
    /// @param self The vault data to operate on
    /// @param shares The number of shares to convert to assets
    /// @param metavaultAsset The address of the metavault asset
    /// @param revertIfStale Whether to revert the transaction if the oracle data is stale
    /// @return assets The equivalent amount of assets for the given shares
    function convertToAssets(
        VaultData memory self,
        uint256 shares,
        address metavaultAsset,
        bool revertIfStale
    )
        internal
        view
        returns (uint256 assets)
    {
        (uint256 sharePrice_, uint64 lastUpdated) =
            self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress, metavaultAsset);
        if (revertIfStale) {
            if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert StaleSharePrice();
        }
        return sharePrice_ * shares / 10 ** self.decimals;
    }

    /// @notice Simulates the ERC4626 {convertToShares} function using vault data
    /// @param self The vault data to operate on
    /// @param assets The number of assets to convert to shares
    /// @param metavaultAsset The address of the metavault asset
    /// @param revertIfStale Whether to revert the transaction if the oracle data is stale
    /// @return shares The equivalent amount of shares for the given assets
    function convertToShares(
        VaultData memory self,
        uint256 assets,
        address metavaultAsset,
        bool revertIfStale
    )
        internal
        view
        returns (uint256 shares)
    {
        (uint256 sharePrice_, uint64 lastUpdated) =
            self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress, metavaultAsset);
        if (revertIfStale) {
            if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert();
        }
        return assets * 10 ** self.decimals / sharePrice_;
    }

    /// @notice Retrieves the current share price of the vault
    /// @param self The vault data to operate on
    /// @param metavaultAsset The address of the metavault asset
    /// @return The current share price
    function sharePrice(VaultData memory self, address metavaultAsset) internal view returns (uint256) {
        (uint256 sharePrice_,) = self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress, metavaultAsset);
        return sharePrice_;
    }

    /// @notice Retrieves the current chain ID
    /// @return chainId The current chain ID
    function _chainId() internal view returns (uint64 chainId) {
        return uint64(block.chainid);
    }
}

/// @notice Parameters for single cross-chain single vault withdrawal
/// @dev Contains data needed for withdrawing from one vault on a different chain
struct SingleXChainSingleVaultWithdraw {
    /// @dev Array of AMB (arbitrary message bridge) IDs to use
    uint8[] ambIds;
    /// @dev Expected output amount from the withdrawal
    uint256 outputAmount;
    /// @dev Maximum acceptable slippage for the withdrawal
    uint256 maxSlippage;
    /// @dev Liquidity request parameters
    LiqRequest liqRequest;
    /// @dev Flag indicating if there's a swap on the destination chain
    bool hasDstSwap;
    /// @dev Native token value to be sent with the transaction
    uint256 value;
}

/// @notice Parameters for single cross-chain multi vault withdrawal
/// @dev Contains data needed for withdrawing from multiple vaults on a different chain
struct SingleXChainMultiVaultWithdraw {
    /// @dev Array of AMB IDs to use
    uint8[] ambIds;
    /// @dev Array of expected output amounts for each vault
    uint256[] outputAmounts;
    /// @dev Array of maximum acceptable slippages for each vault
    uint256[] maxSlippages;
    /// @dev Array of liquidity request parameters for each vault
    LiqRequest[] liqRequests;
    /// @dev Array of flags indicating if there are swaps on the destination chain
    bool[] hasDstSwaps;
    /// @dev Native token value to be sent with the transaction
    uint256 value;
}

/// @notice Parameters for multi cross-chain single vault withdrawal
/// @dev Contains data needed for withdrawing from one vault across multiple chains
struct MultiXChainSingleVaultWithdraw {
    /// @dev 2D array of AMB IDs to use for each chain
    uint8[][] ambIds;
    /// @dev Array of expected output amounts for each chain
    uint256[] outputAmounts;
    /// @dev Array of maximum acceptable slippages for each chain
    uint256[] maxSlippages;
    /// @dev Array of liquidity request parameters for each chain
    LiqRequest[] liqRequests;
    /// @dev Array of flags indicating if there are swaps on destination chains
    bool[] hasDstSwaps;
    /// @dev Native token value to be sent with the transaction
    uint256 value;
}

/// @notice Parameters for multi cross-chain multi vault withdrawal
/// @dev Contains data needed for withdrawing from multiple vaults across multiple chains
struct MultiXChainMultiVaultWithdraw {
    /// @dev 2D array of AMB IDs to use for each chain
    uint8[][] ambIds;
    /// @dev 2D array of expected output amounts for each vault on each chain
    uint256[][] outputAmounts;
    /// @dev 2D array of maximum acceptable slippages for each vault on each chain
    uint256[][] maxSlippages;
    /// @dev 2D array of liquidity request parameters for each vault on each chain
    LiqRequest[][] liqRequests;
    /// @dev 2D array of flags indicating if there are swaps on destination chains
    bool[][] hasDstSwaps;
    /// @dev Native token value to be sent with the transaction
    uint256 value;
}

/// @notice Parameters for processing a redeem request
/// @dev Contains all necessary data to process a withdrawal request
struct ProcessRedeemRequestParams {
    /// @dev Address of the controller initiating the redemption
    address controller;
    /// @dev Number of shares to redeem
    uint256 shares;
    /// @dev Single cross-chain single vault withdrawal parameters
    SingleXChainSingleVaultWithdraw sXsV;
    /// @dev Single cross-chain multi vault withdrawal parameters
    SingleXChainMultiVaultWithdraw sXmV;
    /// @dev Multi cross-chain single vault withdrawal parameters
    MultiXChainSingleVaultWithdraw mXsV;
    /// @dev Multi cross-chain multi vault withdrawal parameters
    MultiXChainMultiVaultWithdraw mXmV;
}
