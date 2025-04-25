// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { IBaseRouter } from "interfaces/Lib.sol";

import { MetaVaultEvents } from "../helpers/MetaVaultEvents.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";

import { MockERC4626 } from "../helpers/mock/MockERC4626.sol";
import { MockERC4626Oracle } from "../helpers/mock/MockERC4626Oracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import { Test, console2 } from "forge-std/Test.sol";

import {
    IMetaVault,
    ISharePriceOracle,
    ISuperformGateway,
    ISuperformRewardsDistributor,
    VaultReport
} from "interfaces/Lib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { ERC7540 } from "lib/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import { AssetsManager, ERC7540Engine, MetaVaultAdmin, RewardsClaimSuperform } from "modules/Lib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { MetaVault } from "src/MetaVault.sol";

import { ERC20Receiver } from "crosschain/Lib.sol";

import { MockRewardsDistributor } from "../helpers/mock/MockRewardsDistributor.sol";
import { MockSwapHandler } from "../helpers/mock/MockSwapHandler.sol";
import {
    EULER_BASE,
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    EXACTLY_USDC_VAULT_OPTIMISM,
    LAYERZERO_ULTRALIGHT_NODE_BASE,
    MORPHO_BASE,
    SUPERFORM_CORE_STATE_REGISTRY_BASE,
    SUPERFORM_LAYERZERO_ENDPOINT_BASE,
    SUPERFORM_LAYERZERO_IMPLEMENTATION_BASE,
    SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_BASE,
    SUPERFORM_PAYMASTER_BASE,
    SUPERFORM_PAYMENT_HELPER_BASE,
    SUPERFORM_ROUTER_BASE,
    SUPERFORM_SUPEREGISTRY_BASE,
    SUPERFORM_SUPERPOSITIONS_BASE,
    UNISWAP_V3_ROUTER_BASE,
    USDCE_BASE
} from "src/helpers/AddressBook.sol";
import { ISharePriceOracle } from "src/interfaces/Lib.sol";
import {
    LiqRequest,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultReport
} from "src/types/Lib.sol";

contract MetaVaultRewardsTest is BaseVaultTest, SuperformActions, MetaVaultEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    AssetsManager manager;
    MetaVaultAdmin admin;
    RewardsClaimSuperform rewards;
    ISuperformGateway public gateway;
    uint32 baseChainId = 8453;
    MockRewardsDistributor public distributor;
    MockSwapHandler public handler;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        config.signerRelayer = relayer;

        vault = IMetaVault(address(new MetaVaultWrapper(config)));
        gateway = deployGatewayBase(address(vault), users.alice);

        admin = new MetaVaultAdmin();
        bytes4[] memory adminSelectors = admin.selectors();
        vault.addFunctions(adminSelectors, address(admin), false);

        vault.setGateway(address(gateway));
        gateway.grantRoles(users.alice, gateway.RELAYER_ROLE());

        engine = new ERC7540Engine();
        bytes4[] memory engineSelectors = engine.selectors();
        vault.addFunctions(engineSelectors, address(engine), false);

        manager = new AssetsManager();
        bytes4[] memory managerSelectors = manager.selectors();
        vault.addFunctions(managerSelectors, address(manager), false);

        rewards = new RewardsClaimSuperform();
        bytes4[] memory rewardsSelectors = rewards.selectors();
        vault.addFunctions(rewardsSelectors, address(rewards), false);

        oracle = new MockERC4626Oracle();
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_BASE.safeApprove(address(vault), type(uint256).max);

        distributor = new MockRewardsDistributor();
        handler = new MockSwapHandler();

        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        console2.log("vault address : %s", address(vault));
        console2.log("recovery address : %s", gateway.recoveryAddress());
    }

    function _setupContractLabels() private {
        vm.label(SUPERFORM_SUPEREGISTRY_BASE, "SuperRegistry");
        vm.label(SUPERFORM_SUPERPOSITIONS_BASE, "SuperPositions");
        vm.label(SUPERFORM_PAYMENT_HELPER_BASE, "PaymentHelper");
        vm.label(SUPERFORM_PAYMASTER_BASE, "PayMaster");
        vm.label(SUPERFORM_LAYERZERO_ENDPOINT_BASE, "LayerZeroEndpoint");
        vm.label(SUPERFORM_CORE_STATE_REGISTRY_BASE, "CoreStateRegistry");
        vm.label(SUPERFORM_ROUTER_BASE, "SuperRouter");
        vm.label(address(vault), "MetaVault");
        vm.label(USDCE_BASE, "USDC");
        vm.label(MORPHO_BASE, "MORPHO");
        vm.label(EULER_BASE, "EULER");
        vm.label(address(oracle), "SharePriceOracle");
        vm.label(address(relayer), "Relayer");
    }

    function setUp() public override {
        super._setUp("BASE", 29_394_833);
        super.setUp();

        _setUpTestEnvironment();
        _setupContractLabels();
    }

    function test_MetaVault_claimRewards() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = MORPHO_BASE;
        rewardTokens[1] = EULER_BASE;
        uint256[] memory amountsClaimed = new uint256[](2);
        amountsClaimed[0] = 100 ether;
        amountsClaimed[1] = 200 ether;

        uint256 totalAssetsBefore = vault.totalAssets();

        IMetaVault.SwapData[] memory swapDatas = new IMetaVault.SwapData[](2);
        // Create swap data for first token - the correct format for your implementation
        swapDatas[0] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[0], USDCE_BASE, amountsClaimed[0])
        );
        // Create swap data for second token
        swapDatas[1] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[1], USDCE_BASE, amountsClaimed[1])
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        vault.totalAssets();
        vault.claimRewardsSuperform(
            address(distributor), 0, rewardTokens, amountsClaimed, new bytes32[](1), swapDatas, minAmountsOut
        );
        assertGt(vault.totalAssets(), totalAssetsBefore);
    }

    function test_MetaVault_claimRewards_swap_failed() public {
        handler.setRevert(true);
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = MORPHO_BASE;
        rewardTokens[1] = EULER_BASE;
        uint256[] memory amountsClaimed = new uint256[](2);
        amountsClaimed[0] = 1 ether;
        amountsClaimed[1] = 2 ether;

        IMetaVault.SwapData[] memory swapDatas = new IMetaVault.SwapData[](2);
        // Create swap data for first token - the correct format for your implementation
        swapDatas[0] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[0], USDCE_BASE, amountsClaimed[0])
        );
        // Create swap data for second token
        swapDatas[1] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[1], USDCE_BASE, amountsClaimed[1])
        );

        uint256[] memory minAmountsOut = new uint256[](2);

        vm.expectRevert(abi.encodeWithSignature("SwapFailedSuperform()"));
        vault.claimRewardsSuperform(
            address(distributor), 0, rewardTokens, amountsClaimed, new bytes32[](1), swapDatas, minAmountsOut
        );
    }

    function test_MetaVault_claimRewards_minOutputNotFilled() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = MORPHO_BASE;
        rewardTokens[1] = EULER_BASE;
        uint256[] memory amountsClaimed = new uint256[](2);
        amountsClaimed[0] = 100 ether;
        amountsClaimed[1] = 200 ether;

        IMetaVault.SwapData[] memory swapDatas = new IMetaVault.SwapData[](2);
        // Create swap data for first token - the correct format for your implementation
        swapDatas[0] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[0], USDCE_BASE, amountsClaimed[0])
        );
        // Create swap data for second token
        swapDatas[1] = IMetaVault.SwapData(
            address(handler),
            abi.encodeWithSelector(MockSwapHandler.swap.selector, rewardTokens[1], USDCE_BASE, amountsClaimed[1])
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1000 ether;
        minAmountsOut[1] = 1000 ether;

        vm.expectRevert(abi.encodeWithSignature("InsufficientSwapOutputSuperform()"));
        vault.claimRewardsSuperform(
            address(distributor), 0, rewardTokens, amountsClaimed, new bytes32[](1), swapDatas, minAmountsOut
        );
    }
}
