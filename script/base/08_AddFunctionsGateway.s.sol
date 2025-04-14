//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { SuperformGateway } from "crosschain/SuperformGateway/SuperformGateway.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "helpers/AddressBook.sol";
import { IBaseRouter, ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";

contract AddFunctionsScript is Script {
    uint256 adminPrivateKey;
    ISuperformGateway public gateway;

    function run() public {
        console2.log("Starting gateway function addition process...");

        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        gateway = ISuperformGateway(payable(vm.envAddress("SUPERFORM_GATEWAY_ADDRESS")));

        console2.log("Adding functions to Gateway at:", address(gateway));

        vm.startBroadcast(adminPrivateKey);

        console2.log("Deploying new Superform modules...");
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();

        bytes4[] memory investSelectors = invest.selectors();
        bytes4[] memory divestSelectors = divest.selectors();
        bytes4[] memory liquidateSelectors = liquidate.selectors();

        console2.log("Adding InvestSuperform functions...");
        console2.log("Number of selectors:", investSelectors.length);
        for (uint256 i = 0; i < investSelectors.length; i++) {
            console2.log(" - Selector:", uint32(investSelectors[i]));
        }
        gateway.addFunctions(investSelectors, address(invest), false);
        console2.log("InvestSuperform functions added successfully");

        console2.log("Adding DivestSuperform functions...");
        console2.log("Number of selectors:", divestSelectors.length);
        for (uint256 i = 0; i < divestSelectors.length; i++) {
            console2.log(" - Selector:", uint32(divestSelectors[i]));
        }
        gateway.addFunctions(divestSelectors, address(divest), false);
        console2.log("DivestSuperform functions added successfully");

        console2.log("Adding LiquidateSuperform functions...");
        console2.log("Number of selectors:", liquidateSelectors.length);
        for (uint256 i = 0; i < liquidateSelectors.length; i++) {
            console2.log(" - Selector:", uint32(liquidateSelectors[i]));
        }
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        console2.log("LiquidateSuperform functions added successfully");

        console2.log("InvestSuperform deployed at:", address(invest));
        console2.log("DivestSuperform deployed at:", address(divest));
        console2.log("LiquidateSuperform deployed at:", address(liquidate));

        vm.stopBroadcast();
    }
}
