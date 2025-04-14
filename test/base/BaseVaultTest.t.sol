// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { BaseTest } from "./BaseTest.t.sol";

import { MockHurdleRateOracle } from "../helpers/mock/MockHurdleRateOracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import {
    IBaseRouter,
    IHurdleRateOracle,
    IMetaVault,
    ISharePriceOracle,
    ISuperPositions,
    ISuperRegistry,
    ISuperformFactory,
    ISuperformGateway
} from "interfaces/Lib.sol";

import { SuperPositionsReceiver } from "crosschain/Lib.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { MetaVault } from "src/MetaVault.sol";
import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    SUPERFORM_FACTORY_BASE,
    SUPERFORM_FACTORY_POLYGON,
    SUPERFORM_ROUTER_BASE,
    SUPERFORM_ROUTER_POLYGON,
    SUPERFORM_SUPEREGISTRY_BASE,
    SUPERFORM_SUPEREGISTRY_POLYGON,
    SUPERFORM_SUPERPOSITIONS_BASE,
    SUPERFORM_SUPERPOSITIONS_POLYGON,
    USDCE_BASE,
    USDCE_POLYGON
} from "src/helpers/AddressBook.sol";
import { VaultConfig } from "types/Lib.sol";

contract BaseVaultTest is BaseTest {
    VaultConfig public config;
    IMetaVault public vault;

    function polygonUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_POLYGON,
            name: "MetaUsdceVault",
            symbol: "metaUSDCe",
            managementFee: 0,
            performanceFee: 0,
            oracleFee: 0,
            hurdleRateOracle: IHurdleRateOracle(address(new MockHurdleRateOracle())),
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON),
            treasury: makeAddr("treasury"),
            signerRelayer: address(new MockSignerRelayer(0xA111ce)),
            owner: users.alice
        });
    }

    function baseChainUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_BASE,
            name: "MetaUsdceVault",
            symbol: "metaUSDCe",
            managementFee: 0,
            performanceFee: 2000,
            oracleFee: 0,
            hurdleRateOracle: IHurdleRateOracle(address(new MockHurdleRateOracle())),
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: makeAddr("treasury"),
            signerRelayer: address(new MockSignerRelayer(0xA111ce)),
            owner: users.alice
        });
    }

    function deployGatewayPolygon(address vault, address owner) public returns (ISuperformGateway) {
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_POLYGON),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON),
            ISuperRegistry(SUPERFORM_SUPEREGISTRY_POLYGON),
            users.alice
        );
        bytes4[] memory investSelectors = invest.selectors();
        gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        ISuperformGateway(address(gateway)).setRecoveryAddress(
            address(new SuperPositionsReceiver(8453, address(gateway), SUPERFORM_SUPERPOSITIONS_BASE, users.alice))
        );
        return ISuperformGateway(address(gateway));
    }

    function deployGatewayBase(address vault, address owner) public returns (ISuperformGateway) {
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_BASE),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            ISuperRegistry(SUPERFORM_SUPEREGISTRY_BASE),
            users.alice
        );
        bytes4[] memory investSelectors = invest.selectors();
        gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        ISuperformGateway(address(gateway)).setRecoveryAddress(
            address(new SuperPositionsReceiver(8453, address(gateway), SUPERFORM_SUPERPOSITIONS_BASE, users.alice))
        );
        return ISuperformGateway(address(gateway));
    }

    function _depositAtomic(uint256 assets, address receiver, address operator) internal returns (uint256 _shares) {
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encodeWithSelector(MetaVault.requestDeposit.selector, assets, receiver, operator);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function _mintAtomic(uint256 shares, address receiver) internal returns (uint256 _assets) {
        bytes[] memory callDatas = new bytes[](2);
        uint256 assets = vault.convertToAssets(shares);
        callDatas[0] = abi.encodeWithSelector(MetaVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("mint(uint256,address)", shares, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }
}
