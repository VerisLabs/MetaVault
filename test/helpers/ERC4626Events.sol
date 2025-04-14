// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract ERC4626Events {
    /// @dev Emitted during a mint call or deposit call.
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted during a withdraw call or redeem call.
    event Withdraw(address indexed by, address indexed to, address indexed owner, uint256 assets, uint256 shares);
}
