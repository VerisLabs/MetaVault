//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperPositionsReceiver } from "crosschain/SuperPositionsReceiver.sol";
import { Script, console2 } from "forge-std/Script.sol";

contract SetGateway is Script {
    SuperPositionsReceiver public receiver;

    uint256 deployerPrivateKey;
    address gatewayAddress;
    address superPositionsReceiverAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        superPositionsReceiverAddress = vm.envAddress("SUPER_POSITIONS_RECEIVER_ADDRESS");

        console2.log("Setting up with following parameters:");
        console2.log("Gateway Address:", gatewayAddress);
        console2.log("SuperPositionsReceiver Address:", superPositionsReceiverAddress);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Setting gateway address on SuperPositionsReceiver...");
        receiver = SuperPositionsReceiver(superPositionsReceiverAddress);
        receiver.setGateway(gatewayAddress);
        console2.log("Gateway address set successfully on SuperPositionsReceiver");

        vm.stopBroadcast();
    }
}
