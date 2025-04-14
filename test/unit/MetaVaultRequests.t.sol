// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { MetaVaultEvents } from "../helpers/MetaVaultEvents.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import { SuperformGatewayEvents } from "../helpers/SuperformGatewayEvents.sol";
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
import {
    AssetsManager, ERC7540Engine, ERC7540EngineReader, ERC7540EngineSignatures, MetaVaultAdmin
} from "modules/Lib.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { MetaVault } from "src/MetaVault.sol";

import { ERC20Receiver } from "crosschain/Lib.sol";
import {
    AAVE_USDC_VAULT_ID_POLYGON,
    AAVE_USDC_VAULT_POLYGON,
    AVVE_USDC_VAULT_ID_OPTIMISM,
    AVVE_USDC_VAULT_OPTIMISM,
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
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultReport
} from "src/types/Lib.sol";

contract MetaVaultRequestsTest is BaseVaultTest, SuperformActions, MetaVaultEvents, SuperformGatewayEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    ERC7540EngineSignatures engineSignatures;
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

        engineSignatures = new ERC7540EngineSignatures();
        bytes4[] memory engineSignaturesSelectors = engineSignatures.selectors();
        vault.addFunctions(engineSignaturesSelectors, address(engineSignatures), false);

        ERC7540EngineReader reader = new ERC7540EngineReader();
        bytes4[] memory readerSelectors = reader.selectors();
        vault.addFunctions(readerSelectors, address(reader), true);

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
        super._setUp("BASE", 26_668_569);
        super.setUp();

        _setUpTestEnvironment();
        _setupContractLabels();
    }

    function test_MetaVault_processRedeemRequest_from_idle() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        skip(config.sharesLockTime);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);
        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, 1000 * _1_USDCE, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, 1000 * _1_USDCE);
    }

    function test_MetaVault_processRedeemRequest_from_local_queue() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        uint256 totalAssetsBeforeLock = vault.totalAssets();
        uint256 sharePriceBeforeLock = vault.sharePrice();
        skip(config.sharesLockTime);
        uint256 totalAssetsAfterLock = vault.totalAssets();
        uint256 sharePriceAfterLock = vault.sharePrice();
        assertEq(totalAssetsAfterLock, totalAssetsBeforeLock);
        assertEq(sharePriceAfterLock, sharePriceBeforeLock);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);
        vault.processRedeemRequest(ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV));
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, totalAssetsAfterLock, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsAfterLock);
    }

    function test_MetaVault_processSignedRedeemRequest() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        skip(config.sharesLockTime);

        uint256 shares = vault.balanceOf(users.alice);

        vault.requestRedeem(shares, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        ProcessRedeemRequestParams memory params =
            ProcessRedeemRequestParams(users.alice, shares, sXsV, sXmV, mXsV, mXmV);

        uint256 deadline = block.timestamp + 1000;
        uint256 nonce = vault.nonces(users.alice);

        // Generate signature from relayer
        bytes32 paramsHash = keccak256(
            abi.encode(
                params.controller, params.shares, params.sXsV, params.sXmV, params.mXsV, params.mXmV, deadline, nonce
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, paramsHash);

        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);

        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);

        uint256 totalAssetsBeforeRedeem = vault.totalAssets();
        // Process request with signature
        vault.processSignedRequest(params, deadline, v, r, s);

        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, totalAssetsBeforeRedeem, sharesBalance);

        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsBeforeRedeem);
    }

    function test_MetaVault_processRedeemRequest_from_local_and_single_xchain_single_vault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

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

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 aliceBalance = vault.balanceOf(users.alice);

        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            oracle.setValues(
                optimismChainId,
                vaultAddress,
                _getSharePrice(optimismChainId, vaultAddress),
                block.timestamp,
                USDCE_BASE,
                users.bob,
                6
            );
        }

        {
            bytes32 requestId;
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;

            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            sXsV.outputAmount = 588 * _1_USDCE;
            uint256 value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);
            sXsV.value = value;
            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, aliceBalance);
            vault.processRedeemRequest{ value: value }(
                ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
            );
            requestId = gateway.getRequestsQueue()[0];
            (,,,, uint128 totalDebt,) = vault.vaults(1);
            assertEq(totalDebt, 0);
            (,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 0);
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.totalSupply(), 0);
            address receiver = gateway.getReceiver(requestId);
            assertEq(USDCE_BASE.balanceOf(receiver), 0);
            assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
            assertEq(vault.claimableRedeemRequest(users.alice), 400_000_053);

            deal(USDCE_BASE, address(receiver), 588 * _1_USDCE);
            gateway.settleLiquidation(requestId, false);
        }
        assertEq(vault.claimableRedeemRequest(users.alice), 999_999_920);
        uint256 assets = vault.redeem(999_999_689, users.alice, users.alice);
        assertEq(assets, 987_999_771);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalIdle(), 0);
    }

    function test_MetaVault_processRedeemRequest_from_local_and_xchain_queue_failed() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

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

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount;

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 aliceBalance = vault.balanceOf(users.alice);

        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            oracle.setValues(
                optimismChainId,
                vaultAddress,
                _getSharePrice(optimismChainId, vaultAddress),
                block.timestamp,
                USDCE_BASE,
                users.bob,
                6
            );
        }

        {
            bytes32 requestId;
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;

            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            sXsV.outputAmount = 588 * _1_USDCE;
            uint256 value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);
            sXsV.value = value;

            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, aliceBalance);
            vault.processRedeemRequest{ value: value }(
                ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
            );
            requestId = gateway.getRequestsQueue()[0];

            (,,,, uint128 totalDebt,) = vault.vaults(1);
            assertEq(totalDebt, 0);
            (,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 0);
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.totalSupply(), 0);

            address receiver = gateway.getReceiver(requestId);
            assertEq(USDCE_BASE.balanceOf(receiver), 0);
            assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
            assertEq(vault.claimableRedeemRequest(users.alice), 400_000_053);

            _mintSuperpositions(gateway.recoveryAddress(), superformId, shares);

            assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
            (,,,, uint128 vaultDebt,) = vault.vaults(superformId);
            assertApproxEq(vaultDebt, 600 * _1_USDCE, _1_USDCE);
            assertEq(vault.totalDebt(), vaultDebt);
            assertApproxEq(vault.totalXChainAssets(), 600 * _1_USDCE, _1_USDCE);
        }
    }

    function test_MetaVault_processRedeemRequest_singleXChainMultiVault() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        // Setup vaults
        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_aloe_op,
            _getSharePrice(optimismChainId, vaultAddress_usdc_aloe_op),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        SingleXChainMultiVaultStateReq memory req = _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        req.superformsData.amounts[0] = amounts[0];
        req.superformsData.amounts[1] = amounts[1];

        uint256 shares_usdc = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares_usdcA = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, amounts[1]);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiVaultDepositValues[multiVaultKey];

        vault.investSingleXChainMultiVault{ value: nativeValue }(req);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares_usdc);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares_usdcA);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        uint256 aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Setup redeem params
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        VaultReport memory report_usdc = oracle.getReport(optimismChainId, vaultAddress_usdc);
        uint256 lastSharePrice = report_usdc.sharePrice;
        VaultReport memory report_usdcp = oracle.getReport(optimismChainId, vaultAddress_usdc_aloe_op);
        uint256 lastSharePrice2 = report_usdcp.sharePrice;

        uint256 expectedDivestedValue1 = lastSharePrice * shares_usdc / 10 ** 6;
        uint256 expectedDivestedValue2 = lastSharePrice2 * shares_usdcA / 10 ** 6;
        uint256 totalExpectedDivestedValue = expectedDivestedValue1 + expectedDivestedValue2;

        SingleXChainMultiVaultStateReq memory divestReq =
            _buildDivestSingleXChainMultiVaultParams(superformIds, amounts);

        sXmV.ambIds = divestReq.ambIds;
        sXmV.outputAmounts = new uint256[](2);
        sXmV.maxSlippages = divestReq.superformsData.maxSlippages;
        sXmV.liqRequests = divestReq.superformsData.liqRequests;
        sXmV.hasDstSwaps = divestReq.superformsData.hasDstSwaps;
        sXmV.value = multiVaultWithdrawValues[multiVaultKey];

        sXmV.outputAmounts[0] = expectedDivestedValue1;
        sXmV.outputAmounts[1] = expectedDivestedValue2;

        uint256 sharePriceBefore = vault.sharePrice();

        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, aliceBalance);
        emit LiquidateXChain(
            users.alice,
            superformIds,
            totalExpectedDivestedValue,
            0x8316e3102cd2e60848d5c003759d83b110bc3bf1846101cd185cfa188aa15a53
        );

        vault.processRedeemRequest{ value: sXmV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );
        uint256 sharePriceAfter = vault.sharePrice();
        assertApproxEq(sharePriceBefore, sharePriceAfter, 1);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 1);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        deal(USDCE_BASE, gateway.getReceiver(requestId), totalExpectedDivestedValue);
        gateway.settleLiquidation(requestId, false);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 0);
    }

    function test_MetaVault_processRedeemRequest_multiXChainSingleVault() public {
        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;

        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;

        uint32 optimismChainId = 10;
        uint32 polygonChainId = 137;

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_optimisim,
            _getSharePrice(optimismChainId, vaultAddress_usdc_optimisim),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_optimisim,
            vault: vaultAddress_usdc_optimisim,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_optimisim),
            oracle: ISharePriceOracle(address(oracle))
        });
        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: polygonChainId,
            superformId: superformId_usdc_pol,
            vault: vaultAddress_usdc_pol,
            vaultDecimals: _getDecimals(polygonChainId, vaultAddress_usdc_pol),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc_optimisim;
        superformIds[1] = superformId_usdc_pol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        MultiDstSingleVaultStateReq memory req = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        req.superformsData[0].amount = 600 * _1_USDCE;
        req.superformsData[1].amount = 600 * _1_USDCE;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress_usdc_optimisim, req.superformsData[0].amount);
        uint256 shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req.superformsData[1].amount);

        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit Invest(1_200_000_000);
        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiChainDepositValues[multiVaultKey];

        vm.startPrank(users.alice);

        vault.investMultiXChainSingleVault{ value: nativeValue }(req);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_optimisim, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        uint256 aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Setup redeem params
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress_usdc_optimisim);
        uint256 lastSharePrice = report.sharePrice;

        VaultReport memory report2 = oracle.getReport(polygonChainId, vaultAddress_usdc_pol);
        uint256 lastSharePrice2 = report2.sharePrice;

        uint256 expectedDivestValuePol = lastSharePrice2 * shares2 / 10 ** 6;
        uint256 expectedDivestValueOptimism = lastSharePrice * shares / 10 ** 6;

        uint256 totalExpectedDivestedValue = expectedDivestValuePol + expectedDivestValueOptimism;

        MultiDstSingleVaultStateReq memory req2 = _buildDivestMultiXChainSingleVaultParams(superformIds, amounts);

        // Set expected output amounts for each superform
        req2.superformsData[0].outputAmount = expectedDivestValuePol; // EXACTLY
        req2.superformsData[1].outputAmount = expectedDivestValueOptimism; // ALOE

        // Initialize arrays in MultiXChainSingleVaultWithdraw struct
        mXsV.ambIds = new uint8[][](2);
        mXsV.outputAmounts = new uint256[](2);
        mXsV.maxSlippages = new uint256[](2);
        mXsV.liqRequests = new LiqRequest[](2);
        mXsV.hasDstSwaps = new bool[](2);

        // Copy data from MultiDstSingleVaultStateReq to MultiXChainSingleVaultWithdraw
        for (uint256 i = 0; i < 2; i++) {
            mXsV.ambIds[i] = req2.ambIds[i];
            mXsV.outputAmounts[i] = req2.superformsData[i].outputAmount;
            mXsV.maxSlippages[i] = req2.superformsData[i].maxSlippage;
            mXsV.liqRequests[i] = req2.superformsData[i].liqRequest;
            mXsV.hasDstSwaps[i] = req2.superformsData[i].hasDstSwap;
        }

        // Set native value for withdrawal
        bytes32 multiVaultKeyWithdraw = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValueWithdraw = multiChainWithdrawValues[multiVaultKeyWithdraw];
        mXsV.value = nativeValueWithdraw;

        uint256 sharePriceBefore = vault.sharePrice();

        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, aliceBalance);
        emit LiquidateXChain(
            users.alice,
            superformIds,
            totalExpectedDivestedValue,
            0x8316e3102cd2e60848d5c003759d83b110bc3bf1846101cd185cfa188aa15a53
        );

        vault.processRedeemRequest{ value: mXsV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );

        uint256 sharePriceAfter = vault.sharePrice();
        assertApproxEq(sharePriceBefore, sharePriceAfter, 1);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 2);

        bytes32 requestId1 = gateway.getRequestsQueue()[0];
        bytes32 requestId2 = gateway.getRequestsQueue()[1];
        deal(USDCE_BASE, gateway.getReceiver(requestId1), expectedDivestValuePol);
        deal(USDCE_BASE, gateway.getReceiver(requestId2), expectedDivestValueOptimism);
        gateway.settleLiquidation(requestId1, false);
        gateway.settleLiquidation(requestId2, false);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 0);
    }

    function test_MetaVault_processRedeemRequest_MultiXChainMultiVault() public {
        // Extract setup into a separate function to reduce local variables
        (
            uint256[] memory superformIds,
            address[] memory vaultAddresses,
            uint256[] memory amounts,
            uint256 shares,
            uint256 shares2,
            uint256 shares3,
            bytes32 multiVaultKey,
            uint256 nativeValue,
            uint256 aliceBalance
        ) = _setupMultiXChainMultiVaultTest();

        // Extract redeem params setup into a separate function
        (
            MultiXChainMultiVaultWithdraw memory mXmV,
            MultiDstMultiVaultStateReq memory req2,
            uint256 expectedDivestValueOptimism,
            uint256 expectedDivestValuePol,
            uint256 totalExpectedDivestedValue,
            uint256 nativeValueWithdraw
        ) = _setupRedeemParams(superformIds, vaultAddresses, shares, shares2, shares3, multiVaultKey);

        uint256 sharePriceBefore = vault.sharePrice();

        vm.startPrank(users.alice);

        // Setup empty structures for other withdrawal types
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;

        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, aliceBalance);
        emit LiquidateXChain(
            users.alice,
            superformIds,
            totalExpectedDivestedValue,
            0x8316e3102cd2e60848d5c003759d83b110bc3bf1846101cd185cfa188aa15a53
        );
        vault.processRedeemRequest{ value: mXmV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );

        uint256 sharePriceAfter = vault.sharePrice();
        assertApproxEq(sharePriceBefore, sharePriceAfter, 1);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 2);

        bytes32 requestId1 = gateway.getRequestsQueue()[0];
        bytes32 requestId2 = gateway.getRequestsQueue()[1];

        deal(USDCE_BASE, gateway.getReceiver(requestId1), expectedDivestValuePol + 140 * _1_USDCE);
        deal(USDCE_BASE, gateway.getReceiver(requestId2), expectedDivestValueOptimism + 140 * _1_USDCE);

        gateway.settleLiquidation(requestId1, false);
        gateway.settleLiquidation(requestId2, false);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalWithdrawableAssets(), 0);
        assertEq(gateway.getRequestsQueue().length, 0);
    }

    // Helper function to set up the test environment
    function _setupMultiXChainMultiVaultTest()
        internal
        returns (
            uint256[] memory superformIds,
            address[] memory vaultAddresses,
            uint256[] memory amounts,
            uint256 shares,
            uint256 shares2,
            uint256 shares3,
            bytes32 multiVaultKey,
            uint256 nativeValue,
            uint256 aliceBalance
        )
    {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;

        uint32 optimismChainId = 10;
        uint32 polygonChainId = 137;

        // Setup vaults
        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_aloe_op,
            _getSharePrice(optimismChainId, vaultAddress_usdc_aloe_op),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: polygonChainId,
            superformId: superformId_usdc_pol,
            vault: vaultAddress_usdc_pol,
            vaultDecimals: _getDecimals(polygonChainId, vaultAddress_usdc_pol),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        superformIds = new uint256[](3);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;
        superformIds[2] = superformId_usdc_aloe_op;

        vaultAddresses = new address[](3);
        vaultAddresses[0] = vaultAddress_usdc;
        vaultAddresses[1] = vaultAddress_usdc_pol;
        vaultAddresses[2] = vaultAddress_usdc_aloe_op;

        amounts = new uint256[](3);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;
        amounts[2] = 600 * _1_USDCE;

        uint256 investAmount = 1800 * _1_USDCE;
        (MultiDstMultiVaultStateReq memory req) = _buildInvestMultiXChainMultiVaultParams(superformIds, amounts);

        req.superformsData[0].amounts[0] = 600 * _1_USDCE;
        req.superformsData[0].amounts[1] = 600 * _1_USDCE;
        req.superformsData[1].amounts[0] = 600 * _1_USDCE;

        shares = _previewDeposit(optimismChainId, vaultAddress_usdc, req.superformsData[0].amounts[0]);
        shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req.superformsData[1].amounts[0]);
        shares3 = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, req.superformsData[0].amounts[1]);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);

        multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        nativeValue = multiChainMultiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investMultiXChainMultiVault{ value: nativeValue }(req);
        vm.stopPrank();

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares3);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        aliceBalance = vault.balanceOf(users.alice);
        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);
        vm.stopPrank();

        return
            (superformIds, vaultAddresses, amounts, shares, shares2, shares3, multiVaultKey, nativeValue, aliceBalance);
    }

    // Helper function to set up redeem parameters
    function _setupRedeemParams(
        uint256[] memory superformIds,
        address[] memory vaultAddresses,
        uint256 shares,
        uint256 shares2,
        uint256 shares3,
        bytes32 multiVaultKey
    )
        internal
        returns (
            MultiXChainMultiVaultWithdraw memory mXmV,
            MultiDstMultiVaultStateReq memory req2,
            uint256 expectedDivestValueOptimism,
            uint256 expectedDivestValuePol,
            uint256 totalExpectedDivestedValue,
            uint256 nativeValueWithdraw
        )
    {
        uint32 optimismChainId = 10;
        uint32 polygonChainId = 137;

        // Initialize mXmV structure
        mXmV.ambIds = new uint8[][](2);
        mXmV.outputAmounts = new uint256[][](2);
        mXmV.maxSlippages = new uint256[][](2);
        mXmV.liqRequests = new LiqRequest[][](2);
        mXmV.hasDstSwaps = new bool[][](2);

        req2 = _buildDivestMultiXChainMultiVaultParamsReedeam();
        req2.superformsData[0].amounts[0] = shares2;
        req2.superformsData[1].amounts[0] = shares;
        req2.superformsData[1].amounts[1] = shares3;

        // Get reports for each vault
        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddresses[0]);
        uint256 lastSharePrice = report.sharePrice;

        VaultReport memory report2 = oracle.getReport(polygonChainId, vaultAddresses[1]);
        uint256 lastSharePrice2 = report2.sharePrice;

        VaultReport memory report3 = oracle.getReport(optimismChainId, vaultAddresses[2]);
        uint256 lastSharePrice3 = report3.sharePrice;

        // Calculate expected values
        expectedDivestValueOptimism = lastSharePrice * shares / 10 ** 6 + lastSharePrice3 * shares3 / 10 ** 6;
        expectedDivestValuePol = lastSharePrice2 * shares2 / 10 ** 6;
        totalExpectedDivestedValue = expectedDivestValueOptimism + expectedDivestValuePol;

        req2.superformsData[0].outputAmounts[0] = expectedDivestValuePol;
        req2.superformsData[1].outputAmounts[0] = expectedDivestValueOptimism / 2;
        req2.superformsData[1].outputAmounts[1] = expectedDivestValueOptimism / 2;

        // Copy data from MultiDstMultiVaultStateReq to MultiXChainMultiVaultWithdraw
        for (uint256 i = 0; i < 2; i++) {
            mXmV.ambIds[i] = req2.ambIds[i];
            mXmV.outputAmounts[i] = req2.superformsData[i].outputAmounts;
            mXmV.maxSlippages[i] = req2.superformsData[i].maxSlippages;
            mXmV.liqRequests[i] = req2.superformsData[i].liqRequests;
            mXmV.hasDstSwaps[i] = req2.superformsData[i].hasDstSwaps;
        }

        nativeValueWithdraw = multiChainMultiVaultWithdrawValues[multiVaultKey];
        mXmV.value = nativeValueWithdraw;

        return (
            mXmV,
            req2,
            expectedDivestValueOptimism,
            expectedDivestValuePol,
            totalExpectedDivestedValue,
            nativeValueWithdraw
        );
    }

    function test_MetaVault_previewWithdrawalRoute() public {
        //// SINGLE XCHIAN MULTI VAULT

        uint256 snapshotId = vm.snapshot();
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        // Setup vaults
        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_aloe_op,
            _getSharePrice(optimismChainId, vaultAddress_usdc_aloe_op),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        SingleXChainMultiVaultStateReq memory req1 = _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        req1.superformsData.amounts[0] = amounts[0];
        req1.superformsData.amounts[1] = amounts[1];

        uint256 shares_usdc = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares_usdcA = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, amounts[1]);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiVaultDepositValues[multiVaultKey];

        vault.investSingleXChainMultiVault{ value: nativeValue }(req1);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares_usdc);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares_usdcA);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        uint256 aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Preview withdrawal route
        ERC7540Engine.ProcessRedeemRequestCache memory cachedRoute = vault.previewWithdrawalRoute(users.alice, 0, false);
        assertTrue(cachedRoute.isSingleChain);
        assertFalse(cachedRoute.isMultiChain);
        assertTrue(cachedRoute.isMultiVault);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// MULTI XCHAIN SINGLE VAULT

        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;

        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;

        uint32 polygonChainId = 137;

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_optimisim,
            _getSharePrice(optimismChainId, vaultAddress_usdc_optimisim),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_optimisim,
            vault: vaultAddress_usdc_optimisim,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_optimisim),
            oracle: ISharePriceOracle(address(oracle))
        });
        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: polygonChainId,
            superformId: superformId_usdc_pol,
            vault: vaultAddress_usdc_pol,
            vaultDecimals: _getDecimals(polygonChainId, vaultAddress_usdc_pol),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        superformIds[0] = superformId_usdc_optimisim;
        superformIds[1] = superformId_usdc_pol;

        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        MultiDstSingleVaultStateReq memory req2 = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        req2.superformsData[0].amount = 600 * _1_USDCE;
        req2.superformsData[1].amount = 600 * _1_USDCE;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress_usdc_optimisim, req2.superformsData[0].amount);
        uint256 shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req2.superformsData[1].amount);

        multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        nativeValue = multiChainDepositValues[multiVaultKey];

        vault.investMultiXChainSingleVault{ value: nativeValue }(req2);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_optimisim, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Preview withdrawal route
        cachedRoute = vault.previewWithdrawalRoute(users.alice, 0, false);
        assertFalse(cachedRoute.isSingleChain);
        assertTrue(cachedRoute.isMultiChain);
        assertFalse(cachedRoute.isMultiVault);

        vm.revertTo(snapshotId);

        /// MULTI XCHAIN MULTI VAULT

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_aloe_op,
            _getSharePrice(optimismChainId, vaultAddress_usdc_aloe_op),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: polygonChainId,
            superformId: superformId_usdc_pol,
            vault: vaultAddress_usdc_pol,
            vaultDecimals: _getDecimals(polygonChainId, vaultAddress_usdc_pol),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        superformIds = new uint256[](3);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;
        superformIds[2] = superformId_usdc_aloe_op;

        amounts = new uint256[](3);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;
        amounts[2] = 600 * _1_USDCE;

        MultiDstMultiVaultStateReq memory req3 = _buildInvestMultiXChainMultiVaultParams(superformIds, amounts);

        req3.superformsData[0].amounts[0] = 600 * _1_USDCE;
        req3.superformsData[0].amounts[1] = 600 * _1_USDCE;
        req3.superformsData[1].amounts[0] = 600 * _1_USDCE;

        shares = _previewDeposit(optimismChainId, vaultAddress_usdc, req3.superformsData[0].amounts[0]);
        shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req3.superformsData[1].amounts[0]);
        uint256 shares3 = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, req3.superformsData[0].amounts[1]);

        multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        nativeValue = multiChainMultiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investMultiXChainMultiVault{ value: nativeValue }(req3);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares3);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Preview withdrawal route
        cachedRoute = vault.previewWithdrawalRoute(users.alice, 0, false);
        assertFalse(cachedRoute.isSingleChain);
        assertTrue(cachedRoute.isMultiChain);
        assertTrue(cachedRoute.isMultiVault);
    }

    function test_previewWithdrawalRoute_despiseDust() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.bob, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

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

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 dustThreshold = 10 * _1_USDCE;
        uint256 dust = _1_USDCE;

        vault.setDustThreshold(dustThreshold);

        shares = vault.convertToShares(vault.totalLocalAssets() + dust);

        ERC7540Engine.ProcessRedeemRequestCache memory cachedRoute =
            vault.previewWithdrawalRoute(users.alice, shares, true);
        assertFalse(cachedRoute.isSingleChain);
        assertFalse(cachedRoute.isMultiChain);
        assertFalse(cachedRoute.isMultiVault);

        assertLt(cachedRoute.shares, shares);
        assertLt(cachedRoute.assets, vault.totalLocalAssets() + dust);
    }

    /// NOTE: this test fixes a bug found in live testing, where the request of a user
    /// could be processed multiple times if crosschain liquidations were involved.
    function test_MetaVault_processRedeemRequest_revertWhenSharesAlreadyBeingProcessed() public {
        // Setup direct test environment without using helper functions
        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;

        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;

        uint32 optimismChainId = 10;
        uint32 polygonChainId = 137;

        // Setup vaults on Optimism and Polygon
        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_optimisim,
            _getSharePrice(optimismChainId, vaultAddress_usdc_optimisim),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_optimisim,
            vault: vaultAddress_usdc_optimisim,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_optimisim),
            oracle: ISharePriceOracle(address(oracle))
        });

        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
        vault.addVault({
            chainId: polygonChainId,
            superformId: superformId_usdc_pol,
            vault: vaultAddress_usdc_pol,
            vaultDecimals: _getDecimals(polygonChainId, vaultAddress_usdc_pol),
            oracle: ISharePriceOracle(address(oracle))
        });

        // Deposit funds
        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        // Setup superformIds and amounts for investment
        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc_optimisim;
        superformIds[1] = superformId_usdc_pol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        // Build investment request
        MultiDstSingleVaultStateReq memory req = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        req.superformsData[0].amount = 600 * _1_USDCE;
        req.superformsData[1].amount = 600 * _1_USDCE;

        // Calculate shares
        uint256 shares = _previewDeposit(optimismChainId, vaultAddress_usdc_optimisim, req.superformsData[0].amount);
        uint256 shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req.superformsData[1].amount);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiChainDepositValues[multiVaultKey];

        // Perform investment
        vm.startPrank(users.alice);
        vault.investMultiXChainSingleVault{ value: nativeValue }(req);
        vm.stopPrank();

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_optimisim, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        // Get Alice's balance and request redemption
        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        uint256 aliceBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        // Setup variables for first redemption process
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress_usdc_optimisim);
        report.sharePrice;

        VaultReport memory report2 = oracle.getReport(polygonChainId, vaultAddress_usdc_pol);
        report2.sharePrice;

        MultiDstSingleVaultStateReq memory req2 = _buildDivestMultiXChainSingleVaultParams(superformIds, amounts);

        // Initialize mXsV for partial redemption
        mXsV.ambIds = new uint8[][](2);
        mXsV.outputAmounts = new uint256[](2);
        mXsV.maxSlippages = new uint256[](2);
        mXsV.liqRequests = new LiqRequest[](2);
        mXsV.hasDstSwaps = new bool[](2);

        // Copy data from MultiDstSingleVaultStateReq to MultiXChainSingleVaultWithdraw
        for (uint256 i = 0; i < 2; i++) {
            mXsV.ambIds[i] = req2.ambIds[i];
            mXsV.outputAmounts[i] = req2.superformsData[i].outputAmount;
            mXsV.maxSlippages[i] = req2.superformsData[i].maxSlippage;
            mXsV.liqRequests[i] = req2.superformsData[i].liqRequest;
            mXsV.hasDstSwaps[i] = req2.superformsData[i].hasDstSwap;
        }

        // Set native value for withdrawal
        bytes32 multiVaultKeyWithdraw = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValueWithdraw = multiChainWithdrawValues[multiVaultKeyWithdraw];
        mXsV.value = nativeValueWithdraw;

        vault.sharePrice();

        vault.processRedeemRequest{ value: mXsV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );

        assertEq(vault.pendingRedeemRequest(users.alice), 1_199_999_830);
        assertEq(vault.pendingProcessedShares(users.alice), 1_199_999_830);

        vm.startPrank(users.bob);

        // Deposit funds as another user
        USDCE_BASE.safeApprove(address(vault), type(uint256).max);
        _depositAtomic(2000 * _1_USDCE, users.bob, users.bob);

        uint256 bobBalance = vault.balanceOf(users.bob);
        vault.requestRedeem(bobBalance, users.bob, users.bob);
        vm.stopPrank();

        // Now vault will try to use idle funds deposited by bob to fulfill the shares that are actually being processed
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("SharesInProcess()"));
        vault.processRedeemRequest{ value: mXsV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );
    }

    function test_MetaVault_processRedeemRequest_refund_flow() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        // Setup vaults
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

        // Deposit funds
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        // Invest in cross-chain vault
        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 sharesAmount = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        req.superformData.amount = investAmount;

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        // Mint superpositions to mock successful investment
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, sharesAmount);

        vm.startPrank(users.alice);
        vault.setSharesLockTime(0);
        uint256 aliceBalance = vault.balanceOf(users.alice);

        // Request redemption
        vault.requestRedeem(aliceBalance, users.alice, users.alice);

        oracle.setValues(
            optimismChainId,
            vaultAddress,
            _getSharePrice(optimismChainId, vaultAddress),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );

        // Setup redemption parameters
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
            _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
        sXsV.outputAmount = 588 * _1_USDCE; // Slightly less due to fees
        sXsV.value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);

        // Process redemption request
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, aliceBalance);

        vault.processRedeemRequest{ value: sXsV.value }(
            ProcessRedeemRequestParams(users.alice, 0, sXsV, sXmV, mXsV, mXmV)
        );

        // Get receiver address from request
        bytes32 requestId = gateway.getRequestsQueue()[0];
        address receiverAddress = gateway.getReceiver(requestId);

        // Verify initial state
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.pendingProcessedShares(users.alice), 599_999_947);
        assertEq(vault.claimableRedeemRequest(users.alice), 400_000_053);

        // Store state before refund for later comparison
        uint256 vaultBalanceBefore = USDCE_BASE.balanceOf(address(vault));
        (,,,, uint128 vaultDebtBefore,) = vault.vaults(superformId);

        vault.sharePrice();

        // Instead of settling with funds, simulate refund by minting SuperPositions back to receiver
        _mintSuperpositions(receiverAddress, superformId, sharesAmount);

        vault.sharePrice();
        assertApproxEq(vault.pendingProcessedShares(users.alice), 0, 100);

        // Verify that the refund was processed correctly
        assertEq(gateway.getRequestsQueue().length, 0); // Request should still be in queue
        assertEq(config.superPositions.balanceOf(address(vault), superformId), sharesAmount);
    }
}
