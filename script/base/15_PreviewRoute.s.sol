//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import {
    LiqRequest,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultWithdraw
} from "types/Lib.sol";

contract PreviewRouteScript is Script {
    IMetaVault public metavault;
    uint256 relayerPrivateKey;

    function run() public {
        relayerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        vm.startBroadcast(relayerPrivateKey);

        address user = 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873;
        uint256 amount;
        uint256 totalLocal = metavault.totalLocalAssets();
        uint256 userRequested = metavault.pendingRedeemRequest(user);

        if (totalLocal < userRequested) {
            amount = totalLocal;
        }

        metavault.previewWithdrawalRoute(user, 0, true);

        console2.log("Previewed withdrawal route");
        console2.log("Amount: ", amount);

        //        SingleXChainSingleVaultWithdraw memory sXsV;
        //        SingleXChainMultiVaultWithdraw memory sXmV;
        //        MultiXChainSingleVaultWithdraw memory mXsV;
        //        MultiXChainMultiVaultWithdraw memory mXmV;
        //
        //        // Call processRedeemRequest
        //        metavault.processRedeemRequest{ value: 0 }(
        //            ProcessRedeemRequestParams({
        //                controller: 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873,
        //                shares: 4000000,
        //                sXsV: sXsV,
        //                sXmV: sXmV,
        //                mXsV: mXsV,
        //                mXmV: mXmV
        //            })
        //        );

        vm.stopBroadcast();
    }
}
