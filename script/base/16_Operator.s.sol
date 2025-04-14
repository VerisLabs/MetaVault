//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";

import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract OperatorScript is Script {
    using SafeTransferLib for address;

    IMetaVault public metavault;
    uint256 deployerPrivateKey;
    uint256 relayerPrivateKey;
    address owner;
    address executor;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        relayerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        owner = 0x429796dAc057E7C15724196367007F1e9Cff82F9;
        executor = 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873;
        vm.startBroadcast(deployerPrivateKey);

        metavault.setOperator(0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873, true);
        metavault.asset().safeApproveWithRetry(executor, 1_000_000);
        metavault.asset().safeTransfer(executor, 1_000_000);

        vm.stopBroadcast();
        vm.startBroadcast(relayerPrivateKey);

        metavault.asset().safeApproveWithRetry(address(metavault), 1_000_000);
        metavault.requestDeposit(1_000_000, owner, executor);
        metavault.deposit(1_000_000, owner, owner);
        vm.stopBroadcast();
    }
}
