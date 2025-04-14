// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract MetaVaultEvents {
    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillRedeemRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @dev Emitted when fees are applied to a user
    event AssessFees(address indexed controller, uint256 managementFees, uint256 performanceFees, uint256 oracleFees);

    /// @dev Emitted when investing vault idle assets
    event Invest(uint256 amount);

    /// @dev Emitted when divesting vault idle assets
    event Divest(uint256 amount);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainInvest(uint256 indexed superformId, uint256 assets);

    /// @dev Emitted when investing vault idle assets
    event Report(uint64 indexed chainId, address indexed vault, int256 amount);

    /// @dev Emitted when adding a new vault to the portfolio
    event AddVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when removing a vault from the portfolio
    event RemoveVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when setting a new oracle for a chain
    event SetOracle(uint64 indexed chainId, address oracle);

    /// @dev Emitted when updating the shares lock time
    event SetSharesLockTime(uint24 time);

    /// @dev Emitted when updating the management fee
    event SetManagementFee(uint16 fee);

    /// @dev Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    /// @dev Emitted when a deposit request is made
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address source, uint256 assets
    );
    /// @dev Emitted when a deposit is completed
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted when assets are withdrawn
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @dev Emitted when an operator is set or unset for a controller
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /// @dev Emitted when the performance fee is set
    event SetPerformanceFee(uint16 fee);
}
