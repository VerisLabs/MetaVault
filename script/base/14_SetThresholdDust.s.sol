//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IMetaVault } from "../../src/interfaces/IMetaVault.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract SetTresholdDust is Script {
    IMetaVault public metavault;

    uint256 deployerPrivateKey;
    address metavaultAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        metavaultAddress = vm.envAddress("METAVAULT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        metavault = IMetaVault(metavaultAddress);
        uint256 dust = metavault.dustThreshold();
        console.log("Actual treshold is set to: ", dust);

        if (dust == 0) {
            metavault.setDustThreshold(3_000_000);
            dust = metavault.dustThreshold();
        }

        console.log("Dust threshold is set to: ", dust);
        vm.stopBroadcast();
    }
}
