//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { SuperformGateway } from "crosschain/SuperformGateway/SuperformGateway.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "helpers/AddressBook.sol";
import { IBaseRouter, ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";

contract RemoveFunctionsScript is Script {
    uint256 adminPrivateKey;
    ISuperformGateway public gateway;
    InvestSuperform invest;
    DivestSuperform divest;
    LiquidateSuperform liquidate;

    function run() public {
        console2.log("Starting gateway function removal process...");

        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        gateway = ISuperformGateway(payable(vm.envAddress("SUPERFORM_GATEWAY_ADDRESS")));

        console2.log("Removing functions from Gateway at:", address(gateway));

        vm.startBroadcast(adminPrivateKey);

        invest = InvestSuperform(vm.envAddress("INVEST_ADDRESS"));
        divest = DivestSuperform(vm.envAddress("DIVEST_ADDRESS"));
        liquidate = LiquidateSuperform(vm.envAddress("LIQUIDATE_ADDRESS"));

        bytes4[] memory investSelectors = invest.selectors();
        bytes4[] memory divestSelectors = divest.selectors();
        bytes4[] memory liquidateSelectors = liquidate.selectors();

        console2.log("Removing InvestSuperform functions...");
        console2.log("Number of selectors:", investSelectors.length);
        for (uint256 i = 0; i < investSelectors.length; i++) {
            console2.log(" - Selector:", uint32(investSelectors[i]));
        }
        gateway.removeFunctions(investSelectors);
        console2.log("InvestSuperform functions removed successfully");

        console2.log("Removing DivestSuperform functions...");
        console2.log("Number of selectors:", divestSelectors.length);
        for (uint256 i = 0; i < divestSelectors.length; i++) {
            console2.log(" - Selector:", uint32(divestSelectors[i]));
        }
        gateway.removeFunctions(divestSelectors);
        console2.log("DivestSuperform functions removed successfully");

        console2.log("Removing LiquidateSuperform functions...");
        console2.log("Number of selectors:", liquidateSelectors.length);
        for (uint256 i = 0; i < liquidateSelectors.length; i++) {
            console2.log(" - Selector:", uint32(liquidateSelectors[i]));
        }
        gateway.removeFunctions(liquidateSelectors);
        console2.log("LiquidateSuperform functions removed successfully");

        vm.stopBroadcast();
    }
}
