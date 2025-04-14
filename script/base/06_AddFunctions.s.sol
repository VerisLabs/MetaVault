//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import { AssetsManager } from "modules/Lib.sol";

contract AddFunctionsScript is Script {
    IMetaVault public metavault;
    uint256 adminPrivateKey;
    ERC7540Engine public engine;
    AssetsManager public assetsManager;

    function run() public {
        console2.log("Starting function addition process...");

        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        vm.startBroadcast(adminPrivateKey);

        console2.log("Deploying new modules...");
        engine = new ERC7540Engine();
        assetsManager = new AssetsManager();

        bytes4[] memory engineSelectors = engine.selectors();
        bytes4[] memory assetsSelectors = assetsManager.selectors();

        console2.log("Adding functions to MetaVault at:", address(metavault));

        console2.log("Adding ERC7540Engine functions...");
        console2.log("Number of selectors:", engineSelectors.length);
        for (uint256 i = 0; i < engineSelectors.length; i++) {
            console2.log(" - Selector:", uint32(engineSelectors[i]));
        }
        metavault.addFunctions(engineSelectors, address(engine), false);
        console2.log("ERC7540Engine functions added successfully");

        console2.log("Adding AssetsManager functions...");
        console2.log("Number of selectors:", assetsSelectors.length);
        for (uint256 i = 0; i < assetsSelectors.length; i++) {
            console2.log(" - Selector:", uint32(assetsSelectors[i]));
        }
        metavault.addFunctions(assetsSelectors, address(assetsManager), true);
        console2.log("AssetsManager functions added successfully");

        console2.log("ERC7540Engine deployed at:", address(engine));
        console2.log("AssetsManager deployed at:", address(assetsManager));

        vm.stopBroadcast();
    }
}
