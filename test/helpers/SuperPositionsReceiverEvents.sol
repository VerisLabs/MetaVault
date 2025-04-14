// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract SuperPositionsReceiverEvents {
    /// @notice Event emitted when tokens are successfully bridged
    /// @param token The address of the token being bridged
    /// @param amount The amount of tokens bridged
    event BridgeInitiated(address indexed token, uint256 amount);
}
