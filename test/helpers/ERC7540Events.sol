// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract ERC7540Events {
    /// @dev Emitted when `assets` tokens are deposited into the vault
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address source, uint256 assets
    );
    /// @dev Emitted when `shares` vault shares are redeemed
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address source, uint256 shares
    );

    /// @dev Emitted when `controller` gives allowance to `operator`
    event OperatorSet(address indexed controller, address indexed operator, bool approved);
}
