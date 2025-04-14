// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { VaultReport } from "src/types/Lib.sol";

contract MockERC4626Oracle {
    mapping(uint32 chainId => mapping(address asset => VaultReport)) public reports;

    function getLatestSharePrice(
        uint32 chainId,
        address vaultAddress,
        address asset
    )
        public
        view
        returns (uint256 sharePrice, uint64 lastUpdated)
    {
        return (reports[chainId][vaultAddress].sharePrice, reports[chainId][vaultAddress].lastUpdate);
    }

    function setValues(
        uint32 chainId,
        address vaultAddress,
        uint256 _sharePrice,
        uint256 _lastUpdated,
        address _asset,
        address _reporter,
        uint8 _decimals
    )
        public
    {
        reports[chainId][vaultAddress] =
            VaultReport(uint192(_sharePrice), uint64(_lastUpdated), chainId, _reporter, vaultAddress, _asset, _decimals);
    }

    function getReport(uint32 chainId, address vault) external returns (VaultReport memory) {
        return reports[chainId][vault];
    }
}
