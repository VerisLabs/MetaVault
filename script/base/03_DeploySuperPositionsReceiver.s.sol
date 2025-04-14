//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SuperPositionsReceiver } from "../../src/crosschain/SuperPositionsReceiver.sol";
import { SUPERFORM_SUPERPOSITIONS_BASE } from "../../src/helpers/AddressBook.sol";
import "forge-std/Script.sol";

contract DeploySuperPositionsReceiver is Script {
    uint256 adminPrivateKey;

    function run() external {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address CREATE2_DEPLOYER = vm.envAddress("CREATE2_DEPLOYER_ADDRESS");
        address GATEWAY = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        address SUPERPOSITIONS = SUPERFORM_SUPERPOSITIONS_BASE;
        address OWNER = vm.envAddress("ADMIN_AND_OWNER_ROLE");

        // Generate bytecode + constructor args dynamically
        bytes memory bytecode = abi.encodePacked(
            type(SuperPositionsReceiver).creationCode, abi.encode(8453, GATEWAY, SUPERPOSITIONS, OWNER)
        );

        vm.startBroadcast(adminPrivateKey);

        bytes32 salt = keccak256(abi.encode(8453, GATEWAY, SUPERPOSITIONS, OWNER));

        (bool success,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, bytecode));
        require(success, "deployment failed");
        vm.stopBroadcast();
    }
}
