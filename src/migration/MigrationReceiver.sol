// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";

import { IMetaVault, ISharePriceOracle, ISuperPositions } from "interfaces/Lib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { VaultData, VaultLib } from "types/Lib.sol";

/// @title MigrationReceiver
/// @author Unlockd
/// @notice Enables secure migration from an old vault to this new vault
/// @dev This module should be added to the "new" vault when performing a vault migration
contract MigrationReceiver is ModuleBase {
    using SafeTransferLib for address;
    using VaultLib for VaultData;
    using SafeCastLib for uint256;

    /// @notice Emitted when a migration is completed successfully
    event MigrationCompleted(
        address indexed sourceVault, uint256 assetsReceived, uint256 sharesIssued, uint256 holderCount
    );

    /// @notice Emiited when dding a new vault
    event AddVault(uint32 chainId, address vault);

    error MaxQueueSizeExceeded();

    /// @notice Migrates assets and user balances from old vault to this vault
    /// @param oldVault The address of the old vault to migrate from
    /// @param holders Array of addresses holding shares in the old vault
    /// @param superPositions SuperPositions contract
    /// @dev Will pull assets and mint appropriate shares to maintain user positions
    function migrateHere(
        address oldVault,
        address[] memory holders,
        ISuperPositions superPositions
    )
        external
        onlyRoles(EMERGENCY_ADMIN_ROLE)
    {
        require(emergencyShutdown == true, "receiver vault must be paused");
        require(oldVault != address(0), "old vault is address 0");
        IMetaVault sender = IMetaVault(oldVault);
        uint256 senderAssets = sender.totalAssets();
        uint256 senderSupply = sender.totalSupply();
        uint256 senderSharePrice = sender.sharePrice();
        uint256 senderIdle = sender.totalIdle();
        uint256 balanceBefore = asset().balanceOf(address(this));
        require(IMigrationSender(oldVault).pullMigration(superPositions), "pulling assets failed");
        uint256 balanceAfter = asset().balanceOf(address(this));
        require(balanceAfter - balanceBefore == senderIdle, "assets not received");
        _totalIdle += senderIdle.toUint128();
        IMetaVault.VaultDetailedData[] memory _vaults = sender.getAllVaultsDetailedData();
        uint256 l = _vaults.length;
        for (uint256 i = 0; i < l; i++) {
            uint256 superformId = _vaults[i].superformId;
                address vaultAddress = _vaults[i].vaultAddress;
                uint32 chainId = _vaults[i].chainId;
            if (!isVaultListed(_vaults[i].superformId)) {
                ISharePriceOracle oracle = _vaults[i].oracle;
                uint8 decimals = _vaults[i].decimals;
                uint128 debt = _vaults[i].totalDebt;

                // Save it into storage
                vaults[superformId].chainId = chainId;
                vaults[superformId].superformId = superformId;
                vaults[superformId].vaultAddress = vaultAddress;
                vaults[superformId].decimals = decimals;
                vaults[superformId].oracle = oracle;
                vaults[superformId].totalDebt = debt;
                _totalDebt += debt;
                uint192 lastSharePrice = vaults[superformId].sharePrice(asset()).toUint192();
                if (lastSharePrice == 0) revert();
                _vaultToSuperformId[vaultAddress] = superformId;

                bool found;

                if (chainId == THIS_CHAIN_ID) {
                    // Push it to the local withdrawal queue
                    uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = localWithdrawalQueue;
                    for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                        if (queue[i] == 0) {
                            localWithdrawalQueue[i] = superformId;
                            found = true;
                            break;
                        }
                    }
                    // If its on the same chain perfom approval to vault
                    asset().safeApprove(vaultAddress, type(uint256).max);
                } else {
                    // Push it to the crosschain withdrawal queue
                    uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = xChainWithdrawalQueue;
                    for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                        if (queue[i] == 0) {
                            xChainWithdrawalQueue[i] = superformId;
                            found = true;
                            break;
                        }
                    }
                }
                if (!found) revert MaxQueueSizeExceeded();

                emit AddVault(chainId, vaultAddress);
            }

            if(chainId == THIS_CHAIN_ID) {
                vaultAddress.safeTransferFrom(address(sender), address(this), vaultAddress.balanceOf(address(sender)));
                
            } else {
                superPositions.safeTransferFrom(
                    address(sender), address(this), superformId, superPositions.balanceOf(address(sender), superformId), ""
                );

            }
        }
        l = holders.length;
        for (uint256 i = 0; i < l; i++) {
            address holder = holders[i];
            uint256 oldBalance = sender.balanceOf(holder);
            if (lastRedeem[holder] == 0) lastRedeem[holder] = block.timestamp;
            positions[holder] = senderSharePrice;
            // uint256 pendingRedeem = sender.pendingRedeemRequest(holder);
            // uint256 claimableRedeem = sender.claimableRedeemRequest(holder);
            // uint256 processedShares = sender.pendingProcessedShares(holder);
            _mint(holder, oldBalance);
        }

        require(totalAssets() == senderAssets, "totalAssets changed");
        require(totalSupply() == senderSupply, "totalSupply changed");
        require(sharePrice() == senderSharePrice, "sharePrice changed");

        // Migration complete
        emit MigrationCompleted(oldVault, senderAssets, senderSupply, l);
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory _selectors = new bytes4[](1);
        _selectors[0] = this.migrateHere.selector;
        return _selectors;
    }
}

/// @notice Interface for the MigrationSender module on the source vault
interface IMigrationSender {
    function pullMigration(ISuperPositions) external returns (bool);
}
