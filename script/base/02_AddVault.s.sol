//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";

contract AddVaultScript is Script {
    IMetaVault public metavault;
    uint32 chainId;
    uint256 superformId;
    address vault;
    uint8 vaultDecimals;
    uint16 deductedFees;
    ISharePriceOracle oracle;
    uint256 deployerPrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        chainId = uint32(vm.envUint("CHAIN_ID")); // 137
        vault = vm.envAddress("NEW_VAULT_ADDRESS"); // 0x60d2cEb7F8d323414a1B927Ee2D9A2A2A54A9824
        superformId = vm.envUint("SUPERFORM_ID"); // 859962937750378607403547653689780213346472919703413156121052
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        vaultDecimals = uint8(vm.envUint("VAULT_DECIMALS")); // 6
        oracle = ISharePriceOracle(vm.envAddress("SHARE_PRICE_ORACLE_ADDRESS")); // 0xA8D4E13b6Afd32F0357a159B79ce9E44391A7149
        vm.startBroadcast(deployerPrivateKey);

        metavault.addVault(chainId, superformId, vault, vaultDecimals, oracle);
        vm.stopBroadcast();
    }
}
