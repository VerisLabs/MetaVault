/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISuperRegistry {
    function getBridgeValidator(uint8 bridgeId_) external view returns (address bridgeValidator_);
}
