// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ISuperPositions } from "interfaces/Lib.sol";


/// @title MigrationSender
/// @author Unlockd
/// @notice Enables secure migration of assets from an old vault to a new vault
/// @dev This module should be added to the "old" vault contract when performing a vault migration
contract MigrationSender is ModuleBase {
    using SafeTransferLib for address;

    /// @notice Emitted when assets are migrated from this vault
    event MigrationPulled(address indexed receiver, uint256 assetAmount, uint256 shareSupply);

    function pullMigration(ISuperPositions sp) external onlyRoles(EMERGENCY_ADMIN_ROLE) returns (bool) {
        require(emergencyShutdown == true, "sender vault must be paused");
        uint256 localBalance = asset().balanceOf(address(this));
        require(_totalIdle == localBalance, "claimable assets pending");
        require(gateway.totalpendingXChainInvests() == 0, "pending invests");
        require(gateway.totalPendingXChainDivests() == 0, "pending divests");
        asset().safeTransfer(msg.sender, localBalance);
        sp.setApprovalForAll(msg.sender, true);
        for(uint256 i=0; i<WITHDRAWAL_QUEUE_SIZE; i++){
            uint256 id = localWithdrawalQueue[i];
            if (id== 0)  break;
            vaults[id].vaultAddress.safeApprove(msg.sender, type(uint256).max);
        }
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
