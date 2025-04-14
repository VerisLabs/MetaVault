//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { ISuperformGateway } from "interfaces/ISuperformGateway.sol";

contract NotifyFailedInvestScript is Script {
    ISuperformGateway public gateway;
    uint256 deployerPrivateKey;
    address gatewayAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        gateway = ISuperformGateway(gatewayAddress);
        gateway.notifyFailedInvest(
            859_962_937_749_922_588_313_557_709_134_519_540_517_673_317_306_582_405_362_791, 5_990_000
        );

        vm.stopBroadcast();
    }
}
