//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperPositionsReceiver } from "crosschain/SuperPositionsReceiver.sol";
import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

contract SetRecoveryAddress is Script {
    ISuperformGateway public gateway;
    SuperPositionsReceiver public receiver;

    uint256 deployerPrivateKey;
    address gatewayAddress;
    address superPositionsReceiverAddress;
    bool updateReceiver;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        superPositionsReceiverAddress = vm.envAddress("SUPER_POSITIONS_RECEIVER_ADDRESS");
        updateReceiver = vm.envBool("UPDATE_RECEIVER");

        console2.log("Setting up with following parameters:");
        console2.log("Gateway Address:", gatewayAddress);
        console2.log("SuperPositionsReceiver Address:", superPositionsReceiverAddress);
        console2.log("Update Receiver:", updateReceiver);

        vm.startBroadcast(deployerPrivateKey);

        // our deployed SuperformGateway contract
        gateway = ISuperformGateway(gatewayAddress);
        console2.log("Setting recovery address on SuperformGateway...");
        gateway.setRecoveryAddress(superPositionsReceiverAddress);
        console2.log("Recovery address set successfully");

        // Also set the gateway on the SuperPositionsReceiver if flag is true
        if (updateReceiver) {
            console2.log("Setting gateway address on SuperPositionsReceiver...");
            receiver = SuperPositionsReceiver(superPositionsReceiverAddress);
            receiver.setGateway(gatewayAddress);
            console2.log("Gateway address set successfully on SuperPositionsReceiver");
        } else {
            console2.log("Skipping SuperPositionsReceiver gateway update as updateReceiver is false");
        }

        vm.stopBroadcast();
    }
}
