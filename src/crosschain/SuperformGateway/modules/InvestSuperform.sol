// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { GatewayBase } from "../common/GatewayBase.sol";
import { IBridgeValidator } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq,
    VaultData
} from "types/Lib.sol";

/// @title InvestSuperform module contract to invest in crosschain ERC4626 vaults using Superform
/// @author Unlockd
/// @notice All this actions are restricted to the portfolio manager role
contract InvestSuperform is GatewayBase {
    using SafeTransferLib for address;

    /// @notice Thrown when an invalid superform ID is provided
    error InvalidSuperformId();

    /// @notice Thrown when an invalid recovery address is provided
    error InvalidRecoveryAddress();

    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();

    /// @notice Thrown when total amounts do not match
    error TotalAmountMismatch();

    /// @notice Thrown when attempting to interact with an unlisted vault
    error VaultNotListed();

    /// @notice Emitted when an investment fails
    event InvestFailed(uint256 indexed superformId, uint256 refundedAssets);

    /// @notice Emitted when pending invest amount is updated
    event PendingInvestUpdated(uint256 indexed superformId, uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when the recovery address is updated
    event RecoveryAddressUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Sets the recovery address for the contract
    /// @dev Only callable by admin role
    /// @param _newRecoveryAddress The new recovery address to set
    function setRecoveryAddress(address _newRecoveryAddress) external onlyRoles(ADMIN_ROLE) {
        if (_newRecoveryAddress == address(0)) revert InvalidRecoveryAddress();
        address oldAddress = recoveryAddress;
        recoveryAddress = _newRecoveryAddress;
        emit RecoveryAddressUpdated(oldAddress, _newRecoveryAddress);
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by the vault address
    /// @param req Crosschain deposit request
    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();

        uint256 superformId = req.superformData.superformId;

        VaultData memory vaultObj = vault.getVault(superformId);

        if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

        uint256 amount;

        if (req.superformData.liqRequest.txData.length != 0) {
            amount = IBridgeValidator(superRegistry.getBridgeValidator(req.superformData.liqRequest.bridgeId))
                .decodeAmountIn(req.superformData.liqRequest.txData, false);
        } else {
            amount = req.superformData.amount;
        }

        asset.safeTransferFrom(address(vault), address(this), amount);

        req.superformData.receiverAddressSP = recoveryAddress;
        req.superformData.receiverAddress = recoveryAddress;

        uint256 oldPendingAmount = pendingXChainInvests[superformId];
        pendingXChainInvests[superformId] += amount;
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += amount;

        // Initiate the cross-chain deposit via the vault router
        superformRouter.singleXChainSingleVaultDeposit{ value: msg.value }(req);

        emit PendingInvestUpdated(superformId, oldPendingAmount, pendingXChainInvests[superformId]);
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);

        return amount;
    }

    /// @notice Invests assets into multiple vaults across a chain
    /// @dev Processes multi-vault deposits and updates pending investment tracking
    /// @param req The cross-chain multi-vault deposit request parameters
    /// @return totalAmount The total amount of assets invested
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
        if (req.superformsData.superformIds.length == 0) revert InvalidAmount();
        if (req.superformsData.superformIds.length != req.superformsData.amounts.length) revert TotalAmountMismatch();
        req.superformsData.receiverAddressSP = address(this);
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];

            req.superformsData.receiverAddressSP = recoveryAddress;
            req.superformsData.receiverAddress = recoveryAddress;

            uint256 amount;

            if (req.superformsData.liqRequests[i].txData.length != 0) {
                amount = IBridgeValidator(superRegistry.getBridgeValidator(req.superformsData.liqRequests[i].bridgeId))
                    .decodeAmountIn(req.superformsData.liqRequests[i].txData, false);
            } else {
                amount = req.superformsData.amounts[i];
            }

            uint256 oldPendingAmount = pendingXChainInvests[superformId];
            pendingXChainInvests[superformId] += amount;
            emit PendingInvestUpdated(superformId, oldPendingAmount, amount);

            totalAmount += amount;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
        }
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.singleXChainMultiVaultDeposit{ value: msg.value }(req);
    }

    /// @notice Invests assets in a single vault across multiple chains
    /// @dev Handles multi-destination deposits for a single vault type
    /// @param req The multi-destination single vault deposit request
    /// @return totalAmount The total amount of assets invested
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
        if (req.superformsData.length == 0) revert InvalidAmount();
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            uint256 amount;

            if (req.superformsData[i].liqRequest.txData.length != 0) {
                amount = IBridgeValidator(superRegistry.getBridgeValidator(req.superformsData[i].liqRequest.bridgeId))
                    .decodeAmountIn(req.superformsData[i].liqRequest.txData, false);
            } else {
                amount = req.superformsData[i].amount;
            }

            req.superformsData[i].receiverAddressSP = recoveryAddress;
            req.superformsData[i].receiverAddress = recoveryAddress;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
            uint256 oldPendingAmount = pendingXChainInvests[superformId];
            pendingXChainInvests[superformId] += amount;
            emit PendingInvestUpdated(superformId, oldPendingAmount, amount);

            totalAmount += amount;
            unchecked {
                ++i;
            }
        }

        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;

        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);

        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
    }

    /// @notice Invests assets in multiple vaults across multiple chains
    /// @dev Processes multi-vault multi-chain deposits
    /// @param req The multi-destination multi-vault deposit request
    /// @return totalAmount The total amount of assets invested
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
        if (req.superformsData.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;
            req.superformsData[i].receiverAddressSP = recoveryAddress;
            req.superformsData[i].receiverAddress = recoveryAddress;

            if (superformIds.length != amounts.length) revert TotalAmountMismatch();
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];
                uint256 amount;

                if (req.superformsData[i].liqRequests[j].txData.length != 0) {
                    amount = IBridgeValidator(
                        superRegistry.getBridgeValidator(req.superformsData[i].liqRequests[j].bridgeId)
                    ).decodeAmountIn(req.superformsData[i].liqRequests[j].txData, false);
                } else {
                    amount = amounts[j];
                }

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);
                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
                uint256 oldPendingAmount = pendingXChainInvests[superformId];
                pendingXChainInvests[superformId] += amount;
                emit PendingInvestUpdated(superformId, oldPendingAmount, amount);
                totalAmount += amount;
            }
        }
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
    }

    /// @notice Handles the cleanup and refund process for failed cross-chain investments
    /// @dev This function is called after assets are recovered from the recovery contract on the destination chain
    ///      It updates the pending investment tracking and processes any refunded assets
    ///      The refunded assets are donated back to the vault to maintain share price accuracy
    /// @param superformId The ID of the Superform position that failed to invest
    /// @param refundedAssets The amount of assets that were recovered and refunded from the destination chain
    function notifyFailedInvest(uint256 superformId, uint256 refundedAssets) external onlyRoles(RELAYER_ROLE) {
        if (superformId == 0) revert InvalidSuperformId();

        uint256 oldAmount = pendingXChainInvests[superformId];
        totalpendingXChainInvests -= oldAmount;
        pendingXChainInvests[superformId] = 0;

        emit PendingInvestUpdated(superformId, oldAmount, 0);
        emit InvestFailed(superformId, refundedAssets);

        if (refundedAssets > 0) {
            asset.safeTransferFrom(msg.sender, address(this), refundedAssets);
            vault.donate(refundedAssets);
        }
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](6);
        s[0] = this.setRecoveryAddress.selector;
        s[1] = this.investSingleXChainSingleVault.selector;
        s[2] = this.investSingleXChainMultiVault.selector;
        s[3] = this.investMultiXChainSingleVault.selector;
        s[4] = this.investMultiXChainMultiVault.selector;

        s[5] = this.notifyFailedInvest.selector;
        return s;
    }
}
