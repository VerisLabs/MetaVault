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

/// @title AssetsManager
/// @notice Implementation of crosschain portfolio-management module
/// @dev Extends ModuleBase contract and implements portfolio management functionalities
contract AssetsManager is ModuleBase {
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

    /// @dev Emitted when investing vault idle assets
    event Invest(uint256 amount);

    /// @dev Emitted when divesting vault idle assets
    event Divest(uint256 amount);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainInvest(uint256 indexed superformId, uint256 assets);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainDivest(uint256 assets);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           INVEST                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Invests assets from this vault into a single target vault within the same chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param vaultAddress The address of the target vault to invest in
    /// @param assets The amount of assets to invest
    /// @param minSharesOut The minimum amount of shares expected to receive from the investment
    /// @return shares The number of shares received from the target vault
    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 assets,
        uint256 minSharesOut
    )
        public
        onlyRoles(MANAGER_ROLE)
        returns (uint256 shares)
    {
        // Ensure the target vault is in the approved list
        if (!isVaultListed(vaultAddress)) revert VaultNotListed();

        // Record the balance before deposit to calculate received shares
        uint256 balanceBefore = vaultAddress.balanceOf(address(this));

        // Deposit assets into the target vault
        ERC4626(vaultAddress).deposit(assets, address(this));

        // Calculate the number of shares received
        shares = vaultAddress.balanceOf(address(this)) - balanceBefore;

        // Ensure the received shares meet the minimum expected assets
        if (shares < minSharesOut) {
            revert InsufficientAssets();
        }

        // Update the vault's internal accounting
        uint128 amountUint128 = assets.toUint128();
        _totalIdle -= amountUint128;
        _totalDebt += amountUint128;
        vaults[_vaultToSuperformId[vaultAddress]].totalDebt += amountUint128;

        emit Invest(assets);
        return shares;
    }

    /// @notice Invests assets from this vault into multiple target vaults within the same chain
    /// @dev Calls investSingleDirectSingleVault for each target vault
    /// @param vaultAddresses An array of addresses of the target vaults to invest in
    /// @param assets An array of amounts to invest in each corresponding vault
    /// @param minSharesOuts An array of minimum amounts of shares expected from each investment
    /// @return shares An array of the number of shares received from each target vault
    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata assets,
        uint256[] calldata minSharesOuts
    )
        external
        returns (uint256[] memory shares)
    {
        shares = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            shares[i] = investSingleDirectSingleVault(vaultAddresses[i], assets[i], minSharesOuts[i]);
        }
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param req Crosschain deposit request
    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 amount = gateway.investSingleXChainSingleVault{ value: msg.value }(req);

        // Update the vault's internal accounting
        uint128 amountUint128 = amount.toUint128();
        _totalIdle -= amountUint128;

        emit Invest(amount);
    }

    /// @notice Placeholder for investing in multiple vaults across chains
    /// @param req Crosschain deposit request
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investSingleXChainMultiVault{ value: msg.value }(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /// @notice Placeholder for investing multiple assets in a single vault across chains
    /// @dev Not implemented yet
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investMultiXChainSingleVault{ value: msg.value }(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /// @notice Placeholder for investing multiple assets in multiple vaults across chains
    /// @dev Not implemented yet
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investMultiXChainMultiVault{ value: msg.value }(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           DIVEST                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Withdraws assets from a single vault on the same chain
    /// @dev This function redeems shares from an ERC4626 vault and updates internal accounting.
    /// If all shares are withdrawn, it removes the total debt for that vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param vaultAddress The address of the vault to withdraw from
    /// @param shares The amount of shares to redeem
    /// @param minAssetsOut The minimum amount of assets expected to receive
    /// @return assets The amount of assets actually withdrawn
    function divestSingleDirectSingleVault(
        address vaultAddress,
        uint256 shares,
        uint256 minAssetsOut
    )
        public
        onlyRoles(MANAGER_ROLE)
        returns (uint256 assets)
    {
        if (!isVaultListed(vaultAddress)) revert VaultNotListed();
        uint256 sharesValue = ERC4626(vaultAddress).convertToAssets(shares).toUint128();

        // Record the balance before deposit to calculate received assets
        uint256 balanceBefore = asset().balanceOf(address(this));

        // Deposit assets into the target vault
        ERC4626(vaultAddress).redeem(shares, address(this), address(this));

        // Calculate the number of assets received
        assets = asset().balanceOf(address(this)) - balanceBefore;

        // Ensure the received assets meet the minimum expected amount
        if (assets < minAssetsOut) {
            revert InsufficientAssets();
        }

        // Update the vault's internal accounting
        _totalIdle += assets.toUint128();
        _totalDebt = _sub0(_totalDebt, sharesValue).toUint128();

        vaults[_vaultToSuperformId[vaultAddress]].totalDebt =
            _sub0(vaults[_vaultToSuperformId[vaultAddress]].totalDebt, sharesValue).toUint128();

        emit Divest(sharesValue);
        return assets;
    }

    /// @notice Withdraws assets from multiple vaults on the same chain
    /// @dev Iteratively calls divestSingleDirectSingleVault for each vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param vaultAddresses Array of vault addresses to withdraw from
    /// @param shares Array of share amounts to withdraw from each vault
    /// @param minAssetsOuts Array of minimum expected asset amounts for each withdrawal
    /// @return assets Array of actual asset amounts withdrawn from each vault
    function divestSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata shares,
        uint256[] calldata minAssetsOuts
    )
        external
        returns (uint256[] memory assets)
    {
        assets = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            assets[i] = divestSingleDirectSingleVault(vaultAddresses[i], shares[i], minAssetsOuts[i]);
        }
    }

    /// @notice Withdraws assets from a single vault on a different chain
    /// @dev Initiates a cross-chain withdrawal through the gateway contract.
    /// Updates debt tracking for the source vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing target chain, vault, and amount details
    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 sharesValue = gateway.divestSingleXChainSingleVault{ value: msg.value }(req, true);
        _totalDebt = _sub0(_totalDebt, sharesValue).toUint128();
        vaults[req.superformData.superformId].totalDebt =
            _sub0(vaults[req.superformData.superformId].totalDebt, sharesValue).toUint128();
        emit Divest(sharesValue);
    }

    /// @notice Withdraws assets from multiple vaults on a single different chain
    /// @dev Processes withdrawals from multiple vaults on the same target chain.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing target chain and multiple vault details
    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.divestSingleXChainMultiVault{ value: msg.value }(req, true);

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
        emit Divest(totalAmount);
    }

    /// @notice Withdraws assets from a single vault across multiple chains
    /// @dev Initiates withdrawals from the same vault type across different chains.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing multiple chain and single vault details
    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.divestMultiXChainSingleVault{ value: msg.value }(req, true);

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
        emit Divest(totalAmount);
    }

    /// @notice Withdraws assets from multiple vaults across multiple chains
    /// @dev Processes withdrawals from different vaults across multiple chains.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing multiple chain and multiple vault details
    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.divestMultiXChainMultiVault{ value: msg.value }(req, true);

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

        emit Divest(totalAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           SETTLEMENT                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Settles a cross-chain investment by updating vault accounting
    /// @param superformId The ID of the superform being settled
    /// @param bridgedAssets The amount of assets that were bridged
    /// @dev Only callable by the gateway contract
    function settleXChainInvest(uint256 superformId, uint256 bridgedAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _totalDebt += bridgedAssets.toUint128();
        vaults[superformId].totalDebt += bridgedAssets.toUint128();
        emit SettleXChainInvest(superformId, bridgedAssets);
    }

    /// @notice Settles a cross-chain divestment by updating vault accounting
    /// @param withdrawnAssets The amount of assets that were withdrawn
    /// @dev Only callable by the gateway contract
    function settleXChainDivest(uint256 withdrawnAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _totalIdle += withdrawnAssets.toUint128();
        emit SettleXChainDivest(withdrawnAssets);
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](14);
        s[0] = this.investSingleDirectSingleVault.selector;
        s[1] = this.investSingleDirectMultiVault.selector;
        s[2] = this.investSingleXChainSingleVault.selector;
        s[3] = this.investSingleXChainMultiVault.selector;
        s[4] = this.investMultiXChainSingleVault.selector;
        s[5] = this.investMultiXChainMultiVault.selector;

        s[6] = this.divestSingleDirectSingleVault.selector;
        s[7] = this.divestSingleDirectMultiVault.selector;
        s[8] = this.divestSingleXChainSingleVault.selector;
        s[9] = this.divestSingleXChainMultiVault.selector;
        s[10] = this.divestMultiXChainSingleVault.selector;
        s[11] = this.divestMultiXChainMultiVault.selector;

        s[12] = this.settleXChainInvest.selector;
        s[13] = this.settleXChainDivest.selector;
        return s;
    }
}
