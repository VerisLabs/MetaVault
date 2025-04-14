// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract SuperformGatewayEvents {
    event LiquidateXChain(
        address indexed controller, uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes32 key
    );
}
