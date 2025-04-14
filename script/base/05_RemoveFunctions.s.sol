//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import { AssetsManager } from "modules/Lib.sol";

contract RemoveFunctionsScript is Script {
    IMetaVault public metavault;
    uint256 adminPrivateKey;
    ERC7540Engine public engine;
    AssetsManager public assetsManager;

    function run() public {
        console2.log("Starting function removal process...");

        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        engine = ERC7540Engine(vm.envAddress("ENGINE_ADDRESS"));
        assetsManager = AssetsManager(vm.envAddress("ASSETS_MANAGER_ADDRESS"));

        console2.log("Removing functions from MetaVault at:", address(metavault));

        vm.startBroadcast(adminPrivateKey);

        bytes4[] memory engineSelectors = engine.selectors();
        bytes4[] memory assetsSelectors = assetsManager.selectors();

        console2.log("Removing ERC7540Engine functions...");
        console2.log("Number of selectors:", engineSelectors.length);
        for (uint256 i = 0; i < engineSelectors.length; i++) {
            console2.log(" - Selector:", uint32(engineSelectors[i]));
        }
        metavault.removeFunctions(engineSelectors);
        console2.log("ERC7540Engine functions removed successfully");

        console2.log("Removing AssetsManager functions...");
        console2.log("Number of selectors:", assetsSelectors.length);
        for (uint256 i = 0; i < assetsSelectors.length; i++) {
            console2.log(" - Selector:", uint32(assetsSelectors[i]));
        }
        metavault.removeFunctions(assetsSelectors);
        console2.log("AssetsManager functions removed successfully");

        vm.stopBroadcast();
    }
}
