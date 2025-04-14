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

import { IMetaVault, ISharePriceOracle, ISuperformGateway, VaultReport } from "interfaces/Lib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { ERC7540 } from "lib/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import { AssetsManager, ERC7540Engine, MetaVaultAdmin } from "modules/Lib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { MetaVault } from "src/MetaVault.sol";

import { ERC20Receiver } from "crosschain/Lib.sol";

import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    EXACTLY_USDC_VAULT_OPTIMISM,
    LAYERZERO_ULTRALIGHT_NODE_BASE,
    SUPERFORM_CORE_STATE_REGISTRY_BASE,
    SUPERFORM_LAYERZERO_ENDPOINT_BASE,
    SUPERFORM_LAYERZERO_IMPLEMENTATION_BASE,
    SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_BASE,
    SUPERFORM_PAYMASTER_BASE,
    SUPERFORM_PAYMENT_HELPER_BASE,
    SUPERFORM_ROUTER_BASE,
    SUPERFORM_SUPEREGISTRY_BASE,
    SUPERFORM_SUPERPOSITIONS_BASE,
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

contract MetaVaultTest is BaseVaultTest, SuperformActions, MetaVaultEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    AssetsManager manager;
    MetaVaultAdmin admin;
    ISuperformGateway public gateway;
    uint32 baseChainId = 8453;

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

        oracle = new MockERC4626Oracle();
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_BASE.safeApprove(address(vault), type(uint256).max);

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
        vm.label(address(oracle), "SharePriceOracle");
        vm.label(address(relayer), "Relayer");
    }

    function setUp() public override {
        super._setUp("BASE", 26_607_127);
        super.setUp();

        _setUpTestEnvironment();
        _setupContractLabels();
    }

    function test_revert_MetaVault_onERC1155Received() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.onERC1155Received(users.alice, address(0), 1, 1, "");
    }

    function test_revert_SuperformGateway_onERC1155Received() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        gateway.onERC1155Received(users.alice, address(0), 1, 1, "");
    }

    function test_MetaVault_initialization() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.asset(), USDCE_BASE);
        assertEq(vault.decimals(), 6);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 2000);
        assertEq(vault.oracleFee(), 0);
        assertEq(vault.hurdleRate(), 600);
        assertEq(vault.lastReport(), block.timestamp);
        assertEq(vault.treasury(), config.treasury);
    }

    function test_MetaVault_depositAtomic() public {
        uint256 amount = 1000 * _1_USDCE;
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 shares = _depositAtomic(amount, users.alice, users.alice);
        assertEq(shares, amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(users.alice), amount);
    }

    function test_MetaVault_mintAtomic() public {
        uint256 amount = 1000 * _1_USDCE;
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 assets = _mintAtomic(amount, users.alice);
        assertEq(assets, amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(users.alice), amount);
    }

    function test_MetaVault_refund_gas() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        oracle.setValues(
            optimismChainId,
            vaultAddress,
            _getSharePrice(optimismChainId, vaultAddress),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: 100 ether }(req);
        assertEq(address(vault).balance, 0);
    }

    function test_MetaVault_addVault() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint32 newChainId = 42;
        uint8 newDecimals = 18;
        oracle.setValues(newChainId, address(newVault), 1e6, block.timestamp, USDCE_BASE, address(1), 0);
        vm.expectEmit(true, true, true, true);
        emit AddVault(newChainId, newVault);
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, ISharePriceOracle(address(oracle)));

        assertTrue(vault.isVaultListed(newVault));
    }

    function test_MetaVault_addVault_ZeroSharePrice() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint32 newChainId = 42;
        uint8 newDecimals = 18;

        vm.expectRevert();
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, ISharePriceOracle(address(oracle)));
    }

    function test_revert_MetaVault_addVault_alreadyListed() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        uint8 decimals = yUsdce.decimals();
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: ISharePriceOracle(address(oracle))
        });
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vm.expectRevert(MetaVault.VaultAlreadyListed.selector);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: ISharePriceOracle(address(oracle))
        });
    }

    function test_MetaVault_removeVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        uint256 superformId = 1;
        uint8 decimals = yUsdce.decimals();

        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: superformId,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: ISharePriceOracle(address(oracle))
        });

        assertTrue(vault.isVaultListed(address(yUsdce)));

        vm.expectEmit(true, true, true, true);
        emit RemoveVault(baseChainId, address(yUsdce));

        vault.removeVault(superformId);

        assertFalse(vault.isVaultListed(address(yUsdce)));
    }

    function test_MetaVault_rearrangeWithdrawalQueue() public {
        // Setup 3 vaults
        MockERC4626 vault1 = new MockERC4626(USDCE_BASE, "Vault1", "V1", true, 0);
        MockERC4626 vault2 = new MockERC4626(USDCE_BASE, "Vault2", "V2", true, 0);
        MockERC4626 vault3 = new MockERC4626(USDCE_BASE, "Vault3", "V3", true, 0);

        // Add vaults to MetaVault
        oracle.setValues(baseChainId, address(vault1), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        oracle.setValues(baseChainId, address(vault2), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        oracle.setValues(baseChainId, address(vault3), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(vault1),
            vaultDecimals: vault1.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(vault2),
            vaultDecimals: vault2.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        vault.addVault({
            chainId: baseChainId,
            superformId: 3,
            vault: address(vault3),
            vaultDecimals: vault3.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        // Create new order array (all zeros by default)
        uint256[30] memory newOrder;
        // Set new order: [3,1,2,0,0,...]
        newOrder[0] = 3;
        newOrder[1] = 1;
        newOrder[2] = 2;

        // Rearrange local withdrawal queue (type 0)
        vault.rearrangeWithdrawalQueue(0, newOrder);

        // Verify new order
        assertEq(vault.localWithdrawalQueue(0), 3);
        assertEq(vault.localWithdrawalQueue(1), 1);
        assertEq(vault.localWithdrawalQueue(2), 2);
        assertEq(vault.localWithdrawalQueue(3), 0); // Rest should be zero
    }

    function test_revert_MetaVault_rearrangeWithdrawalQueue_invalidQueueType() public {
        uint256[30] memory newOrder;
        vm.expectRevert(MetaVault.InvalidQueueType.selector);
        vault.rearrangeWithdrawalQueue(2, newOrder); // Only 0 and 1 are valid
    }

    function test_revert_MetaVault_rearrangeWithdrawalQueue_duplicateVault() public {
        // Setup vault
        MockERC4626 vault1 = new MockERC4626(USDCE_BASE, "Vault1", "V1", true, 0);
        oracle.setValues(baseChainId, address(vault1), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(vault1),
            vaultDecimals: vault1.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        // Create new order with duplicate entries
        uint256[30] memory newOrder;
        newOrder[0] = 1;
        newOrder[1] = 1; // Duplicate entry

        vm.expectRevert(MetaVault.DuplicateVaultInOrder.selector);
        vault.rearrangeWithdrawalQueue(0, newOrder);
    }

    function test_revert_MetaVault_removeVault_withBalance() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        uint256 superformId = 1;
        uint8 decimals = yUsdce.decimals();

        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: superformId,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: ISharePriceOracle(address(oracle))
        });

        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        uint256 investAmount = 500 * _1_USDCE;
        uint256 shares = yUsdce.previewDeposit(investAmount);
        vault.investSingleDirectSingleVault(address(yUsdce), investAmount, shares);

        vm.expectRevert(MetaVault.SharesBalanceNotZero.selector);
        vault.removeVault(superformId);

        // Verify vault is still listed
        assertTrue(vault.isVaultListed(address(yUsdce)));
    }

    function test_MetaVault_setSharesLockTime() public {
        uint24 newLockTime = 152_700; // 12 hours

        vm.expectEmit(true, true, true, true);
        emit SetSharesLockTime(newLockTime);
        vault.setSharesLockTime(newLockTime);

        assertEq(vault.sharesLockTime(), newLockTime);
    }

    function test_revert_MetaVault_setSharesLockTime_exceedsMax() public {
        uint24 invalidTime = 182_700;

        vm.startPrank(users.alice);

        vm.expectRevert(MetaVaultAdmin.InvalidSharesLockTime.selector);
        vault.setSharesLockTime(invalidTime);

        assertEq(vault.sharesLockTime(), config.sharesLockTime);

        vm.stopPrank();
    }

    function test_MetaVault_setManagementFee() public {
        uint16 newFee = 1500;

        vm.startPrank(users.alice);

        vm.expectEmit(true, true, true, true);
        emit SetManagementFee(newFee);
        vault.setManagementFee(newFee);

        assertEq(vault.managementFee(), newFee);

        vm.stopPrank();
    }

    function test_revert_MetaVault_setManagementFee_exceedsMax() public {
        vm.startPrank(users.alice);

        uint16 tooHighFee = 10_001; // 100.01%

        vm.expectRevert(MetaVaultAdmin.FeeExceedsMaximum.selector);
        vault.setManagementFee(tooHighFee);

        assertEq(vault.managementFee(), 0);

        vm.stopPrank();
    }

    function test_MetaVault_setOracleFee() public {
        uint16 newFee = 2000;

        vm.expectEmit(true, true, true, true);
        emit SetOracleFee(newFee);
        vault.setOracleFee(newFee);

        assertEq(vault.oracleFee(), newFee);
    }

    function test_revert_MetaVault_emergencyShutdown() public {
        vault.setEmergencyShutdown(true);

        vm.expectRevert(MetaVault.VaultShutdown.selector);
        vault.requestDeposit(100 * _1_USDCE, users.alice, users.alice);
    }

    function test_revert_MetaVault_invalidController() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        vm.startPrank(users.bob);
        vm.expectRevert(ERC7540.InvalidController.selector);
        vault.deposit(amount, users.bob, users.alice);
    }

    function test_MetaVault_setOperator() public {
        uint256 amount = 100 * _1_USDCE;
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(users.alice, users.bob, true);
        vault.setOperator(users.bob, true);
        vault.requestDeposit(amount, users.alice, users.alice);
        vm.stopPrank();

        assertTrue(vault.isOperator(users.alice, users.bob));

        vm.startPrank(users.bob);
        vault.deposit(amount, users.alice, users.alice);
    }

    function test_revert_MetaVault_setOperator_invalidOperator() public {
        vm.expectRevert(ERC7540.InvalidOperator.selector);
        vault.setOperator(users.alice, true);
    }

    function test_MetaVault_notifyFailedInvest() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        oracle.setValues(
            optimismChainId,
            vaultAddress,
            _getSharePrice(optimismChainId, vaultAddress),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory investReq =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        investReq.superformData.amount = investAmount;

        _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );

        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 400 * _1_USDCE);
        assertEq(gateway.totalpendingXChainInvests(), 600 * _1_USDCE);

        deal(USDCE_BASE, users.alice, investAmount);
        vm.startPrank(users.alice);
        USDCE_BASE.safeApprove(address(gateway), type(uint256).max);
        gateway.notifyFailedInvest(superformId, investAmount);
        vm.stopPrank();

        assertEq(gateway.totalpendingXChainInvests(), 0);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
    }

    function test_MetaVault_exitFees_withProfit() public {
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        uint256 profit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        // With 1000 USDC deposit and 100 USDC profit, share price should be ~1.1e6
        uint256 expectedSharePrice = 1_100_000; // 1.1e6
        assertApproxEq(vault.sharePrice(), expectedSharePrice, 1);

        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));

        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;

        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 excessReturn = profit > hurdleReturn ? profit - hurdleReturn : 0;

        uint256 expectedPerformanceFees = excessReturn * vault.performanceFee() / vault.MAX_BPS();
        uint256 expectedManagementFees =
            (totalAssets * duration * vault.managementFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 expectedOracleFees =
            (totalAssets * duration * vault.oracleFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        uint256 totalExpectedFees = expectedPerformanceFees + expectedManagementFees + expectedOracleFees;
        uint256 totalExpectedFeesShares = vault.convertToShares(totalExpectedFees);

        if (totalExpectedFees > excessReturn) {
            totalExpectedFees = excessReturn;
            uint256 totalFeeBps = vault.performanceFee() + vault.managementFee() + vault.oracleFee();
            expectedPerformanceFees = (expectedPerformanceFees * excessReturn) / totalFeeBps;
            expectedManagementFees = (expectedManagementFees * excessReturn) / totalFeeBps;
            expectedOracleFees = (expectedOracleFees * excessReturn) / totalFeeBps;
        }

        vm.expectEmit(true, true, true, true);
        emit AssessFees(users.alice, expectedManagementFees, expectedPerformanceFees - 1, expectedOracleFees);

        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        assertEq(receivedAssets, totalAssets - totalExpectedFees);
        assertApproxEq(vault.balanceOf(vault.treasury()), totalExpectedFeesShares, 1);
    }

    function test_MetaVault_chargeGlobalFees_positives() public {
        vault.setManagementFee(100);
        vault.setOracleFee(50);
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        skip(180 days);

        uint256 profit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 lastSharePrice = vault.sharePriceWaterMark();
        uint256 lastTotalAssets = (totalSupplyBefore * lastSharePrice) / (10 ** vault.decimals());
        uint256 currentSharePrice = vault.sharePrice();

        uint256 totalAssetsBeforeFees = totalAssets;

        uint256 managementFees =
            (totalAssets * duration * vault.managementFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = (totalAssets * duration * vault.oracleFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        totalAssets += managementFees + oracleFees;

        uint256 hurdleReturn =
            (lastTotalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        int256 assetsDelta = int256(totalAssets) - int256(lastTotalAssets);

        uint256 performanceFees;
        if (assetsDelta > 0) {
            uint256 totalReturn = uint256(assetsDelta);

            if (currentSharePrice > lastSharePrice && totalReturn > hurdleReturn) {
                uint256 excessReturn = totalReturn - hurdleReturn;
                performanceFees = excessReturn * vault.performanceFee() / vault.MAX_BPS();
            }
        }

        uint256 totalFees = managementFees + performanceFees + oracleFees;

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, performanceFees, oracleFees);
        uint256 actualFees = vault.chargeGlobalFees();

        uint256 expectedShares = (totalFees * totalSupplyBefore) / totalAssetsBeforeFees;

        uint256 actualTreasuryShares = vault.balanceOf(vault.treasury()) - treasurySharesBefore;

        vm.stopPrank();

        assertEq(actualFees, totalFees);
        assertEq(actualTreasuryShares, expectedShares);
    }

    function test_MetaVault_chargeGlobalFees_BelowWatermark() public {
        vault.setManagementFee(100);
        vault.setOracleFee(50);
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        vault.setManagementFee(100);
        vault.setOracleFee(50);
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        uint256 initialProfit = 200 * _1_USDCE;
        deal(USDCE_BASE, users.bob, initialProfit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), initialProfit);
        vault.donate(initialProfit);
        vm.stopPrank();

        vm.prank(users.alice);
        vault.chargeGlobalFees();
        uint256 highWatermark = vault.sharePrice();
        vm.stopPrank();

        uint256 loss = 250 * _1_USDCE;
        uint256 lostShares = yUsdce.convertToShares(loss);
        vm.startPrank(address(vault));
        address(yUsdce).safeTransfer(users.bob, lostShares);
        vm.stopPrank();

        uint256 recovery = 50 * _1_USDCE;
        deal(USDCE_BASE, users.bob, recovery);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), recovery);
        vault.donate(recovery);
        vm.stopPrank();

        skip(180 days);

        assertLt(vault.sharePrice(), highWatermark);

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());
        uint256 totalSupplyBefore = vault.totalSupply();

        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 totalFees = managementFees + oracleFees;

        // Calculate expected shares using pre-fee ratio
        uint256 expectedShares = (totalFees * totalSupplyBefore) / totalAssets;

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees); // No performance fees
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        assertEq(actualFees, totalFees);
        assertEq(vault.balanceOf(vault.treasury()) - treasurySharesBefore, expectedShares);
    }

    function test_MetaVault_chargeGlobalFees_BelowHurdleRate() public {
        vault.setManagementFee(100);
        vault.setOracleFee(50);
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        skip(180 days);

        uint256 smallProfit = 10 * _1_USDCE; // Very small profit
        deal(USDCE_BASE, users.bob, smallProfit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), smallProfit);
        vault.donate(smallProfit);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());
        uint256 totalSupplyBefore = vault.totalSupply();

        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 totalFees = managementFees + oracleFees;

        // Calculate expected shares using pre-fee ratio
        uint256 expectedShares = (totalFees * totalSupplyBefore) / totalAssets;

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees);
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        assertEq(actualFees, totalFees);
        // Check the actual share amount minted to treasury
        assertEq(vault.balanceOf(vault.treasury()) - treasurySharesBefore, expectedShares);
    }

    function test_MetaVault_chargeGlobalFees_NoProfit() public {
        vault.setManagementFee(100);
        vault.setOracleFee(50);
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        skip(180 days);

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());
        uint256 totalSupplyBefore = vault.totalSupply();

        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 totalFees = managementFees + oracleFees;

        // Calculate expected shares using pre-fee ratio
        uint256 expectedShares = (totalFees * totalSupplyBefore) / totalAssets;

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees);
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        assertEq(actualFees, totalFees);
        assertEq(vault.balanceOf(vault.treasury()) - treasurySharesBefore, expectedShares);
    }

    function test_MetaVault_exitFees_noExcessReturn() public {
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        vault.setOracleFee(0);

        uint256 profit = 1 * _1_USDCE; // Very small profit
        deal(USDCE_BASE, users.bob, profit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));

        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;
        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        assertLe(profit, hurdleReturn);

        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        assertEq(receivedAssets, totalAssets - 1);
        assertEq(USDCE_BASE.balanceOf(vault.treasury()), 0);
    }

    function test_MetaVault_exitFees_belowWatermark_noPerformanceFees() public {
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        uint256 initialProfit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, initialProfit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), initialProfit);
        vault.donate(initialProfit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        uint256 watermark = vault.sharePrice();

        uint256 loss = 150 * _1_USDCE;
        vm.startPrank(address(vault));
        USDCE_BASE.safeTransfer(users.bob, loss);
        MetaVaultWrapper(payable(address(vault))).setTotalIdle(uint128((1000 + 100 - 150) * _1_USDCE));
        vm.stopPrank();

        uint256 recoveryProfit = 50 * _1_USDCE;
        deal(USDCE_BASE, users.bob, recoveryProfit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), recoveryProfit);
        vault.donate(recoveryProfit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        assertLt(vault.sharePrice(), watermark);

        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));

        uint256 vaultBalanceBefore = USDCE_BASE.balanceOf(address(vault));

        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        uint256 expectedTotalAssets = depositAmount + initialProfit - loss + recoveryProfit;

        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 managementFee =
            (expectedTotalAssets * duration * vault.managementFee()) / (vault.SECS_PER_YEAR() * vault.MAX_BPS());
        uint256 oracleFee =
            (expectedTotalAssets * duration * vault.oracleFee()) / (vault.SECS_PER_YEAR() * vault.MAX_BPS());
        uint256 expectedFees = managementFee + oracleFee;

        uint256 expectedReceivedAssets = expectedTotalAssets - expectedFees;

        // Assertions
        assertEq(receivedAssets, expectedReceivedAssets, "Received assets don't match expected");
        assertEq(USDCE_BASE.balanceOf(vault.treasury()), expectedFees, "Treasury fees don't match expected");
        assertEq(
            USDCE_BASE.balanceOf(address(vault)), vaultBalanceBefore - receivedAssets, "Vault balance change incorrect"
        );
    }

    function test_MetaVault_exitFees_feeExemption() public {
        vault.setManagementFee(100);
        vault.setOracleFee(50);
        vault.setManagementFee(100);
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        vm.startPrank(users.bob);
        uint256 performanceFeeExemption = 1000; // 10%
        uint256 managementFeeExemption = 500; // 5%
        uint256 oracleFeeExemption = 200; // 2%
        vm.stopPrank();

        vm.startPrank(users.alice);
        vault.setFeeExcemption(users.alice, managementFeeExemption, performanceFeeExemption, oracleFeeExemption);

        vm.startPrank(users.bob);
        uint256 profit = 2000 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);
        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));

        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;

        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 excessReturn = profit - hurdleReturn;

        uint256 expectedPerformanceFees =
            excessReturn * _sub0(vault.performanceFee(), performanceFeeExemption) / vault.MAX_BPS();
        uint256 expectedManagementFees = (totalAssets * duration * _sub0(vault.managementFee(), managementFeeExemption))
            / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 expectedOracleFees = (totalAssets * duration * _sub0(vault.oracleFee(), oracleFeeExemption))
            / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        uint256 totalExpectedFees = expectedPerformanceFees + expectedManagementFees + expectedOracleFees;
        uint256 totalExpectedFeesShares = vault.convertToShares(totalExpectedFees);

        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertApproxEq(receivedAssets, 1000 * _1_USDCE + profit - totalExpectedFees, 2);
        assertApproxEq(address(vault).balanceOf(vault.treasury()), totalExpectedFeesShares, 2);
    }

    function test_revert_MetaVault_setManagementFee_nonAdmin() public {
        uint16 newFee = 1500;

        vm.startPrank(users.bob);
        vm.expectRevert();
        vault.setManagementFee(newFee);
        vm.stopPrank();

        assertEq(vault.managementFee(), 0);
    }

    function test_revert_MetaVault_setPerformanceFee_nonAdmin() public {
        uint16 newFee = 1500;

        vm.startPrank(users.bob);
        vm.expectRevert();
        vault.setPerformanceFee(newFee);
        vm.stopPrank();

        assertEq(vault.performanceFee(), 2000);
    }

    function test_revert_MetaVault_setOracleFee_nonAdmin() public {
        uint16 newFee = 1500;

        vm.startPrank(users.bob);
        vm.expectRevert();
        vault.setOracleFee(newFee);
        vm.stopPrank();

        assertEq(vault.oracleFee(), 0);
    }

    function test_revert_MetaVault_setPerformanceFee_exceedsMax() public {
        vm.startPrank(users.alice);

        uint16 tooHighFee = 10_001; // MAX_FEE is 3000 (30%)

        vm.expectRevert(MetaVaultAdmin.FeeExceedsMaximum.selector);
        vault.setPerformanceFee(tooHighFee);

        assertEq(vault.performanceFee(), 2000);

        vm.stopPrank();
    }

    function test_revert_MetaVault_setOracleFee_exceedsMax() public {
        vm.startPrank(users.alice);

        uint16 tooHighFee = 10_001; // MAX_FEE is 3000 (30%)

        vm.expectRevert(MetaVaultAdmin.FeeExceedsMaximum.selector);
        vault.setOracleFee(tooHighFee);

        assertEq(vault.oracleFee(), 0);

        vm.stopPrank();
    }

    function test_MetaVault_convertToSuperPositions() public {
        uint256 superformId = 1;
        uint256 assets = 100 * _1_USDCE;

        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);

        vault.addVault({
            chainId: baseChainId,
            superformId: superformId,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        uint256 superPositions = vault.convertToSuperPositions(superformId, assets);
        assertGt(superPositions, 0);
    }

    function test_MetaVault_chargeGlobalFees_zeroFees() public {
        vault.setManagementFee(0);
        vault.setPerformanceFee(0);
        vault.setOracleFee(0);

        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice, users.alice);

        skip(180 days);

        vm.startPrank(users.alice);
        uint256 fees = vault.chargeGlobalFees();
        vm.stopPrank();

        assertEq(fees, 0);
    }

    function test_MetaVault_setPerformanceFee() public {
        uint16 newFee = 1500;

        vm.startPrank(users.alice);

        vm.expectEmit(true, true, true, true);
        emit SetPerformanceFee(newFee);
        vault.setPerformanceFee(newFee);

        assertEq(vault.performanceFee(), newFee);
        vm.stopPrank();
    }

    function test_revert_MetaVault_setSharesLockTime_tooHigh() public {
        uint24 tooHighTime = 72 hours;

        vm.startPrank(users.alice);
        vm.expectRevert(MetaVaultAdmin.InvalidSharesLockTime.selector);
        vault.setSharesLockTime(tooHighTime);
        vm.stopPrank();
    }

    function test_MetaVault_feeExemption() public {
        vm.startPrank(users.alice);

        uint256 managementFeeExemption = 500; // 5%
        uint256 performanceFeeExemption = 1000; // 10%
        uint256 oracleFeeExemption = 200; // 2%

        vault.setFeeExcemption(users.bob, managementFeeExemption, performanceFeeExemption, oracleFeeExemption);

        assertEq(vault.managementFeeExempt(users.bob), managementFeeExemption);
        assertEq(vault.performanceFeeExempt(users.bob), performanceFeeExemption);
        assertEq(vault.oracleFeeExempt(users.bob), oracleFeeExemption);

        vm.stopPrank();
    }

    function test_MetaVault_donate() public {
        uint256 donationAmount = 1000 * _1_USDCE;

        uint256 vaultBalanceBefore = USDCE_BASE.balanceOf(address(vault));
        uint256 totalIdleBefore = vault.totalIdle();

        vm.startPrank(users.alice);
        USDCE_BASE.safeApprove(address(vault), donationAmount);
        vault.donate(donationAmount);
        vm.stopPrank();

        assertEq(USDCE_BASE.balanceOf(address(vault)), vaultBalanceBefore + donationAmount);
        assertEq(vault.totalIdle(), totalIdleBefore + donationAmount);
    }
}
