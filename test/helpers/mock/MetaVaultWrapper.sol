// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { MetaVault, VaultConfig } from "src/MetaVault.sol";

contract MetaVaultWrapper is MetaVault {
    constructor(VaultConfig memory config) MetaVault(config) { }

    function setTotalIdle(uint128 newIdle) public {
        _totalIdle = newIdle;
    }
}
