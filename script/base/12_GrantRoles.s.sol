//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

contract GrantGatewayRoles is Script {
    ISuperformGateway public gateway;

    uint256 deployerPrivateKey;
    address relayerAddress;
    address gatewayAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        relayerAddress = vm.envAddress("RELAYER_ROLE");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        gateway = ISuperformGateway(gatewayAddress);
        gateway.grantRoles(relayerAddress, gateway.RELAYER_ROLE());

        vm.stopBroadcast();
    }
}
