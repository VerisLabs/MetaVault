// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";

import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
    LiqRequest,
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
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

/// @title EmergencyAssetsManager
/// @notice Emergency module for recovering cross-chain assets when normal bridging routes are unavailable
/// @dev This module provides emergency functions to divest assets from vaults across chains when standard
/// bridging paths are compromised or inaccessible. The assets are recovered manually by authorized admins.
/// The module updates internal accounting but skips the normal receiver validation to allow manual recovery.
contract EmergencyAssetsManager is ModuleBase {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           LIBRARIES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

    /// @notice Thrown when attempting to interact with a vault that is not listed in the portfolio
    error VaultNotListed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when assets are emergency divested from vaults
    event EmergencyDivest(uint256 amount);

    /// @dev Emitted when cross-chain emergency divestment is settled
    event SettleXChainDivest(uint256 assets);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EMERGENCY DIVEST                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emergency withdrawal of assets from a single vault on a different chain
    /// @dev Initiates a cross-chain withdrawal through the gateway contract without receiver validation.
    /// Updates debt tracking for the source vault. Only callable by emergency admins.
    /// @param req The withdrawal request containing target chain, vault, and amount details
    function emergencyDivestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(EMERGENCY_ADMIN_ROLE)
    {
        uint256 sharesValue = gateway.divestSingleXChainSingleVault{ value: msg.value }(req, false);
        _totalDebt = _sub0(_totalDebt, sharesValue).toUint128();
        vaults[req.superformData.superformId].totalDebt =
            _sub0(vaults[req.superformData.superformId].totalDebt, sharesValue).toUint128();
        emit EmergencyDivest(sharesValue);
    }

    /// @notice Emergency withdrawal of assets from multiple vaults on a single different chain
    /// @dev Processes emergency withdrawals from multiple vaults on the same target chain.
    /// Updates debt tracking for all source vaults. Only callable by emergency admins.
    /// @param req The withdrawal request containing target chain and multiple vault details
    function emergencyDivestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(EMERGENCY_ADMIN_ROLE)
    {
        uint256 totalAmount = gateway.divestSingleXChainMultiVault{ value: msg.value }(req, false);

        for (uint256 i = 0; i < req.superformsData.superformIds.length;) {
            uint256 superformId = req.superformsData.superformIds[i];
            VaultData memory vault = vaults[superformId];
            uint256 divestAmount = vault.convertToAssets(req.superformsData.amounts[i], asset(), true);
            vault.totalDebt = _sub0(vaults[superformId].totalDebt, divestAmount).toUint128();
            vaults[superformId] = vault;
            unchecked {
                ++i;
            }
        }
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();
        emit EmergencyDivest(totalAmount);
    }

    /// @notice Emergency withdrawal of assets from a single vault across multiple chains
    /// @dev Initiates emergency withdrawals from the same vault type across different chains.
    /// Updates debt tracking for all source vaults. Only callable by emergency admins.
    /// @param req The withdrawal request containing multiple chain and single vault details
    function emergencyDivestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(EMERGENCY_ADMIN_ROLE)
    {
        uint256 totalAmount = gateway.divestMultiXChainSingleVault{ value: msg.value }(req, false);

        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            VaultData memory vault = vaults[superformId];
            uint256 divestAmount = vault.convertToAssets(req.superformsData[i].amount, asset(), true);
            vault.totalDebt = _sub0(vaults[superformId].totalDebt, divestAmount).toUint128();
            vaults[superformId] = vault;
            unchecked {
                ++i;
            }
        }
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();
        emit EmergencyDivest(totalAmount);
    }

    /// @notice Emergency withdrawal of assets from multiple vaults across multiple chains
    /// @dev Processes emergency withdrawals from different vaults across multiple chains.
    /// Updates debt tracking for all source vaults. Only callable by emergency admins.
    /// @param req The withdrawal request containing multiple chain and multiple vault details
    function emergencyDivestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(EMERGENCY_ADMIN_ROLE)
    {
        uint256 totalAmount = gateway.divestMultiXChainMultiVault{ value: msg.value }(req, false);

        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            for (uint256 j = 0; j < superformIds.length;) {
                uint256 superformId = superformIds[j];
                VaultData memory vault = vaults[superformId];
                uint256 divestAmount = vault.convertToAssets(req.superformsData[i].amounts[j], asset(), true);
                vault.totalDebt = _sub0(vaults[superformId].totalDebt, divestAmount).toUint128();
                vaults[superformId] = vault;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();

        emit EmergencyDivest(totalAmount);
    }

    /// @notice Returns the function selectors supported by this module
    /// @dev Used for module registration and discovery
    /// @return Array of 4-byte function selectors for all emergency divest functions
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](4);
        s[0] = this.emergencyDivestMultiXChainMultiVault.selector;
        s[1] = this.emergencyDivestMultiXChainSingleVault.selector;
        s[2] = this.emergencyDivestSingleXChainMultiVault.selector;
        s[3] = this.emergencyDivestSingleXChainSingleVault.selector;
        return s;
    }
}
