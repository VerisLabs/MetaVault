// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";
import { IHurdleRateOracle } from "interfaces/IHurdleRateOracle.sol";
import { ISharePriceOracle } from "interfaces/ISharePriceOracle.sol";
import { ISuperformGateway } from "interfaces/ISuperformGateway.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { VaultData } from "types/Lib.sol";

/// @title MetaVaultAdmin
/// @author Unlockd
/// @notice Admin module for MetaVault that contains all the admin functions
/// @dev This module extracts admin functions from the main MetaVault contract to reduce its size
contract MetaVaultAdmin is ModuleBase {
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when attempting to set a fee higher than the maximum allowed
    error FeeExceedsMaximum();

    /// @notice Thrown when attempting to set a shares lock time higher than the maximum allowed
    error InvalidSharesLockTime();

    /// @notice Thrown when an invalid zero address is encountered
    error InvalidZeroAddress();

    /// @notice Thrown when an invalid oracle address is provided
    error InvalidOracleAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the gateway address is updated
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);

    /// @notice Emitted when the hurdle rate oracle is updated
    event HurdleRateOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when the vault oracle is updated
    event VaultOracleUpdated(uint256 indexed superformId, address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when updating the shares lock time
    event SetSharesLockTime(uint24 time);

    /// @notice Emitted when updating the management fee
    event SetManagementFee(uint16 fee);

    /// @notice Emitted when updating the performance fee
    event SetPerformanceFee(uint16 fee);

    /// @notice Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    /// @notice Emitted when the treasury address is updated
    event TreasuryUpdated(address indexed treasury);

    /// @notice Emitted when the emergency shutdown state is changed
    event EmergencyShutdown(bool enabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the gateway contract for cross-chain communication
    /// @param _gateway The address of the new gateway contract
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setGateway(ISuperformGateway _gateway) external onlyRoles(ADMIN_ROLE) {
        address oldGateway = address(gateway);

        if (oldGateway != address(0)) {
            gateway.superPositions().setApprovalForAll(oldGateway, false);
            asset().safeApprove(oldGateway, 0);
        }

        gateway = _gateway;
        asset().safeApprove(address(_gateway), type(uint256).max);
        gateway.superPositions().setApprovalForAll(address(_gateway), true);

        emit GatewayUpdated(oldGateway, address(_gateway));
    }

    /// @notice Sets the hurdle rate oracle for performance fee calculations
    /// @param hurdleRateOracle The new oracle address to set
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setHurdleRateOracle(IHurdleRateOracle hurdleRateOracle) external onlyRoles(ADMIN_ROLE) {
        address oldOracle = address(_hurdleRateOracle);
        _hurdleRateOracle = hurdleRateOracle;
        emit HurdleRateOracleUpdated(oldOracle, address(hurdleRateOracle));
    }

    /// @notice Sets the oracle for a specific vault
    /// @param superformId The ID of the superform to set the oracle for
    /// @param oracle The new oracle address to set
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setVaultOracle(uint256 superformId, ISharePriceOracle oracle) external onlyRoles(ADMIN_ROLE) {
        if (address(oracle) == address(0)) revert InvalidOracleAddress();
        address oldOracle = address(vaults[superformId].oracle);
        vaults[superformId].oracle = oracle;
        emit VaultOracleUpdated(superformId, oldOracle, address(oracle));
    }

    /// @notice Sets the lock time for shares in the vault.
    /// @dev Only callable by addresses with ADMIN_ROLE.
    /// @param _time The lock time to set for shares, must not exceed MAX_TIME.
    function setSharesLockTime(uint24 _time) external onlyRoles(ADMIN_ROLE) {
        if (_time > MAX_TIME) revert InvalidSharesLockTime();
        sharesLockTime = _time;
        emit SetSharesLockTime(_time);
    }

    /// @notice Sets the treasury address for the vault
    /// @dev Only callable by addresses with ADMIN_ROLE
    /// @param _treasury The address of the treasury
    function setTreasury(address _treasury) external onlyRoles(ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidZeroAddress();
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Sets the annual management fee
    /// @param _managementFee New BPS management fee
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setManagementFee(uint16 _managementFee) external onlyRoles(ADMIN_ROLE) {
        if (_managementFee > MAX_FEE) revert FeeExceedsMaximum();
        managementFee = _managementFee;
        emit SetManagementFee(_managementFee);
    }

    /// @notice Sets the annual performance fee
    /// @param _performanceFee New BPS performance fee
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setPerformanceFee(uint16 _performanceFee) external onlyRoles(ADMIN_ROLE) {
        if (_performanceFee > MAX_FEE) revert FeeExceedsMaximum();
        performanceFee = _performanceFee;
        emit SetPerformanceFee(_performanceFee);
    }

    /// @notice Sets the annual oracle fee
    /// @param _oracleFee New BPS oracle fee
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setOracleFee(uint16 _oracleFee) external onlyRoles(ADMIN_ROLE) {
        if (_oracleFee > MAX_FEE) revert FeeExceedsMaximum();
        oracleFee = _oracleFee;
        emit SetOracleFee(_oracleFee);
    }

    /// @notice Sets custom fee exemptions for specific clients
    /// @param controller The address of the client to exempt
    /// @param managementFeeExcemption The management fee exemption amount in BPS
    /// @param performanceFeeExcemption The performance fee exemption amount in BPS
    /// @param oracleFeeExcemption The oracle fee exemption amount in BPS
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setFeeExcemption(
        address controller,
        uint256 managementFeeExcemption,
        uint256 performanceFeeExcemption,
        uint256 oracleFeeExcemption
    )
        external
        onlyRoles(ADMIN_ROLE)
    {
        performanceFeeExempt[controller] = performanceFeeExcemption;
        managementFeeExempt[controller] = managementFeeExcemption;
        oracleFeeExempt[controller] = oracleFeeExcemption;
    }

    /// @notice Sets the emergency shutdown state of the vault
    /// @dev Can only be called by addresses with the EMERGENCY_ADMIN_ROLE
    /// @param _emergencyShutdown True to enable emergency shutdown, false to disable
    function setEmergencyShutdown(bool _emergencyShutdown) external onlyRoles(EMERGENCY_ADMIN_ROLE) {
        emergencyShutdown = _emergencyShutdown;
        emit EmergencyShutdown(_emergencyShutdown);
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](10);
        s[0] = this.setGateway.selector;
        s[1] = this.setHurdleRateOracle.selector;
        s[2] = this.setVaultOracle.selector;
        s[3] = this.setSharesLockTime.selector;
        s[4] = this.setTreasury.selector;
        s[5] = this.setManagementFee.selector;
        s[6] = this.setPerformanceFee.selector;
        s[7] = this.setOracleFee.selector;
        s[8] = this.setFeeExcemption.selector;
        s[9] = this.setEmergencyShutdown.selector;
        return s;
    }
}
