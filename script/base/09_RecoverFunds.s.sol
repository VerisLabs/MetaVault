//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperPositionsReceiver } from "crosschain/SuperPositionsReceiver.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract RecoverFundsScript is Script {
    using SafeTransferLib for address;

    uint256 adminPrivateKey;
    SuperPositionsReceiver public receiver;

    function run() public {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        // recovery address
        receiver = SuperPositionsReceiver(vm.envAddress("SUPERFORM_RECEIVER_ADDRESS"));

        vm.startBroadcast(adminPrivateKey);

        address usdce = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        uint256 balance = usdce.balanceOf(address(receiver));

        receiver.recoverFunds(usdce, balance, address(this));

        vm.stopBroadcast();
    }
}
