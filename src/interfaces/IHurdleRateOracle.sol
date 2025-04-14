/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHurdleRateOracle {
    function getRate(address asset) external view returns (uint256);
}
