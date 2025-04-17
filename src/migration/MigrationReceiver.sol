// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import { ModuleBase } from "common/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import {IMetaVault} from "interfaces/Lib.sol";

/// @title MigrationReceiver
/// @author Unlockd
/// @notice Enables secure migration from an old vault to this new vault
/// @dev This module should be added to the "new" vault when performing a vault migration
contract MigrationReceiver is ModuleBase {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    /// @notice Emitted when a migration is completed successfully
    event MigrationCompleted(
        address indexed sourceVault, 
        uint256 assetsReceived, 
        uint256 sharesIssued, 
        uint256 holderCount
    );

    /// @notice Interface for the MigrationSender module on the source vault
    interface IMigrationSender {
        function pullMigration() external returns (bool);
    }

    /// @notice Migrates assets and user balances from old vault to this vault
    /// @param sourceVault The address of the old vault to migrate from
    /// @param holders Array of addresses holding shares in the old vault
    /// @dev Will pull assets and mint appropriate shares to maintain user positions
    function migrateHere(address oldVault, address[] memory holders) external onlyRoles(EMERGENCY_ADMIN_ROLE) {
        require(emergencyShutdown == true, "receiver vault must be paused");
        require(oldVault != address(0), "old vault is address 0");
        IMetaVault sender = IMetaVault(oldVault);
        uint256 senderAssets = sender.totalAssets();
        uint256 senderSupply = sender.totalSupply();
        uint256 senderSharePrice = sender.sharePrice();
        uint256 balanceBefore = asset().balanceOf(address(this));
        require(SenderVault(oldVault).pullMigration(),"pulling assets failed");
        uint256 balanceAfter = asset().balanceOf(address(this));
        require(balanceAfter - balanceBefore  == senderAssets, "assets not received");
        _totalIdle += senderAssets.toUint128();
        uint256 l = holders.length;
        for(uint256 i=0; i < l; i++) {
            address holder = holders[i];
            uint256 oldBalance = sender.balanceOf(holder);
            if (lastRedeem[holder] == 0) lastRedeem[holder] = block.timestamp;
            positions[holder] = senderSharePrice;
            _mint(holder, oldBalance);
        }
        console2.log("new sharePrice : ", sharePrice());
        console2.log("new assets : ", totalAssets());
        console2.log("new shares : ", totalSupply());
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