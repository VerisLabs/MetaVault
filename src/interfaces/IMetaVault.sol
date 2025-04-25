/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ISharePriceOracle } from "./ISharePriceOracle.sol";

import { ERC7540Engine } from "modules/Lib.sol";
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
    VaultConfig,
    VaultData,
    VaultLib
} from "types/Lib.sol";

interface IMetaVault {
    function WITHDRAWAL_QUEUE_SIZE() external view returns (uint256);

    function SECS_PER_YEAR() external view returns (uint256);

    function MAX_BPS() external view returns (uint256);

    function ADMIN_ROLE() external view returns (uint256);

    function MANAGER_ROLE() external view returns (uint256);

    function RELAYER_ROLE() external view returns (uint256);

    function ORACLE_ROLE() external view returns (uint256);

    function EMERGENCY_ADMIN_ROLE() external view returns (uint256);

    function N_CHAINS() external view returns (uint256);

    function THIS_CHAIN_ID() external view returns (uint64);

    function DST_CHAINS(uint256) external view returns (uint64);

    function treasury() external view returns (address);

    function signerRelayer() external view returns (address);

    function gateway() external view returns (address);

    function emergencyShutdown() external view returns (bool);

    function localWithdrawalQueue(uint256) external view returns (uint256);

    function xChainWithdrawalQueue(uint256) external view returns (uint256);

    function performanceFeeExempt(address) external view returns (uint256);

    function managementFeeExempt(address) external view returns (uint256);

    function oracleFeeExempt(address) external view returns (uint256);

    function grantRoles(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function asset() external view returns (address);

    function totalAssets() external view returns (uint256 assets);

    function totalSupply() external view returns (uint256 assets);

    function convertToAssets(uint256) external view returns (uint256);

    function convertToShares(uint256) external view returns (uint256);

    function convertToSuperPositions(uint256 superformId, uint256 assets) external view returns (uint256);

    function totalWithdrawableAssets() external view returns (uint256 assets);

    function totalLocalAssets() external view returns (uint256 assets);

    function totalXChainAssets() external view returns (uint256 assets);

    function sharePrice() external view returns (uint256);

    function totalIdle() external view returns (uint256 assets);

    function totalDebt() external view returns (uint256 assets);

    function totalDeposits() external view returns (uint256 assets);

    function managementFee() external view returns (uint256);

    function sharesLockTime() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    function oracleFee() external view returns (uint256);

    function hurdleRate() external view returns (uint256);

    function lastReport() external view returns (uint256);

    function addVault(
        uint32 chainId,
        uint256 superformId,
        address vault,
        uint8 vaultDecimals,
        ISharePriceOracle oracle
    )
        external;

    function removeVault(uint256 superformId) external;

    function rearrangeWithdrawalQueue(uint8 queueType, uint256[30] calldata newOrder) external;

    function vaults(uint256) external view returns (uint32, uint256, ISharePriceOracle, uint8, uint128, address);

    function isVaultListed(address vaultAddress) external view returns (bool);

    function isVaultListed(uint256 superformId) external view returns (bool);

    function getVault(uint256 superformId) external view returns (VaultData memory vault);

    function setOperator(address, bool) external;

    function isOperator(address, address) external view returns (bool);

    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    function deposit(uint256 assets, address to) external returns (uint256 shares);

    function deposit(uint256 assets, address to, address controller) external returns (uint256 shares);

    function mint(uint256 shares, address to) external returns (uint256 assets);

    function mint(uint256 shares, address to, address controller) external returns (uint256 assets);

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    function pendingRedeemRequest(address) external view returns (uint256);

    function claimableRedeemRequest(address) external view returns (uint256);

    function pendingProcessedShares(address) external view returns (uint256);

    function pendingDepositRequest(address) external view returns (uint256);

    function claimableDepositRequest(address) external view returns (uint256);

    function processRedeemRequest(ProcessRedeemRequestParams calldata params) external payable;

    function processSignedRequest(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external;

    function nonces(address) external view returns (uint256);

    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 assets,
        uint256 minSharesOut
    )
        external
        returns (uint256 shares);

    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata assets,
        uint256[] calldata minSharesOuts
    )
        external
        returns (uint256[] memory shares);

    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function divestSingleDirectSingleVault(
        address vaultAddress,
        uint256 shares,
        uint256 minAssetsOut
    )
        external
        returns (uint256 assets);

    function divestSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata shares,
        uint256[] calldata minAssetsOuts
    )
        external
        returns (uint256[] memory assets);

    function setFeeExcemption(
        address controller,
        uint256 managementFeeExcemption,
        uint256 performanceFeeExcemption,
        uint256 oracleFeeExcemption
    )
        external;

    function sharePriceWaterMark() external view returns (uint256);

    function lastRedeem(address) external view returns (uint256);

    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function emergencyDivestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function emergencyDivestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function emergencyDivestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function emergencyDivestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function setEmergencyShutdown(bool _emergencyShutdown) external;

    function setGateway(address) external;

    function donate(uint256 assets) external;

    function setSharesLockTime(uint24 time) external;

    function setManagementFee(uint16 _managementFee) external;

    function setPerformanceFee(uint16 _performanceFee) external;

    function setOracleFee(uint16 _oracleFee) external;

    function setRecoveryAddress(address _recoveryAddress) external;

    function fulfillSettledRequest(address controller, uint256 requestedAssets, uint256 settledAssets) external;

    function settleXChainInvest(uint256 superformId, uint256 bridgedAssets) external;

    function settleXChainDivest(uint256 withdrawn) external;

    function multicall(bytes[] calldata data) external returns (bytes[] memory);

    function addFunction(bytes4, address, bool) external;

    function addFunctions(bytes4[] memory, address, bool) external;

    function removeFunction(bytes4) external;

    function removeFunctions(bytes4[] memory) external;

    function lastFeesCharged() external view returns (uint256);

    function chargeGlobalFees() external returns (uint256);

    function previewWithdrawalRoute(
        address controller,
        uint256 shares,
        bool despiseDust
    )
        external
        view
        returns (ERC7540Engine.ProcessRedeemRequestCache memory cachedRoute);

    function setDustThreshold(uint256 dustThreshold) external;

    function dustThreshold() external view returns (uint256);

    function computeHash(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce
    )
        external
        pure
        returns (bytes32);

    function verifySignature(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        view
        returns (bool);

    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        external
        returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        external
        returns (bytes4);

    /// @notice Detailed data structure for a vault
    /// @dev Contains key vault parameters and current state
    struct VaultDetailedData {
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
        /// @dev Owned vault shares
        uint256 sharesBalance;
        /// @dev Share price of the vault
        uint256 sharePrice;
        /// @dev Total assets managed by vault
        uint256 totalAssets;
    }

    function getVaultDetailedData(uint256 superformId) external view returns (VaultDetailedData memory);

    function getAllVaultsDetailedData() external view returns (VaultDetailedData[] memory);

    /// @notice Data structure for vault return metrics
    /// @dev Contains total, hurdle and excess returns
    struct VaultReturnsData {
        /// @dev Total return generated by the vault
        uint256 totalReturn;
        /// @dev Minimum return required before performance fees
        uint256 hurdleReturn;
        /// @dev Returns above the hurdle rate
        uint256 excessReturn;
    }

    function getLastEpochVaultReturns() external view returns (VaultReturnsData memory);

    function totalReturnsPerShare() external view returns (int256);

    struct SwapData {
        address target;
        bytes data;
    }

    function claimRewardsSuperform(
        address rewardsDistributor,
        uint256 periodId,
        address[] memory rewardTokens,
        uint256[] memory amountsClaimed,
        bytes32[] memory proof,
        SwapData[] memory swapDatas,
        uint256[] memory minAmountsOut
    )
        external;

    function batchClaimRewardsSuperform(
        address rewardsDistributor,
        uint256[] memory periodIds,
        address[][] memory rewardTokens,
        uint256[][] memory amountsClaimed,
        bytes32[][] memory proofs,
        SwapData[][] memory swapDatas,
        uint256[][] memory minAmountsOut
    )
        external;
}
