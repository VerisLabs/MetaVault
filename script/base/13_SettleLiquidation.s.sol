//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

contract GrantGatewayRoles is Script {
    ISuperformGateway public gateway;

    uint256 relayerPrivateKey;
    address gatewayAddress;

    function run() public {
        relayerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        vm.startBroadcast(relayerPrivateKey);

        gateway = ISuperformGateway(gatewayAddress);
        gateway.settleLiquidation(0x84b10f05ac9f3815ebe03402d2765777ac9611e4d0de00f6b010d16ec6a21e55, false);

        vm.stopBroadcast();
    }
}
