// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import { ModuleBase } from "common/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";


/// @title MigrationSender
/// @author Unlockd
/// @notice Enables secure migration of assets from an old vault to a new vault
/// @dev This module should be added to the "old" vault contract when performing a vault migration
contract MigrationSender is ModuleBase {
    using SafeTransferLib for address;

     /// @notice Emitted when assets are migrated from this vault
    event MigrationPulled(address indexed receiver, uint256 assetAmount, uint256 shareSupply);

    function pullMigration() external onlyRoles(EMERGENCY_ADMIN_ROLE) returns(bool){
        require(emergencyShutdown == true, "sender vault must be paused");
        uint256 localBalance = asset().balanceOf(address(this));
        require(_totalIdle == localBalance, "claimable assets pending");
        require(totalXChainAssets() == 0, "xchain assets invested");
        require(totalLocalAssets() == _totalIdle, "local assets invested");
        asset().safeTransfer(msg.sender, localBalance);
        emit MigrationPulled(msg.sender, localBalance, totalSupply());
        return true;
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory _selectors = new bytes4[](1);
        _selectors[0] = this.pullMigration.selector;
        return _selectors;
    }
}