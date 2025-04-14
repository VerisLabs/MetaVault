// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
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
import { AssetsManager, ERC7540Engine, EmergencyAssetsManager, MetaVaultAdmin } from "modules/Lib.sol";

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
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq,
    VaultReport
} from "src/types/Lib.sol";

contract MetaVaultDivestTest is BaseVaultTest, SuperformActions, MetaVaultEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    AssetsManager manager;
    EmergencyAssetsManager emergencyManager;
    ISuperformGateway public gateway;
    MetaVaultAdmin admin;
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

        emergencyManager = new EmergencyAssetsManager();
        bytes4[] memory emergencySelectors = emergencyManager.selectors();
        vault.addFunctions(emergencySelectors, address(emergencyManager), false);

        oracle = new MockERC4626Oracle();
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_BASE.safeApprove(address(vault), type(uint256).max);
        USDCE_BASE.safeApprove(address(gateway), type(uint256).max);

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

    function test_MetaVault_divestSingleDirectSingleVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
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

        uint256 sharesToDivest = yUsdce.balanceOf(address(vault));
        uint256 minAssetsOut = yUsdce.convertToAssets(sharesToDivest) - 1;

        vm.expectEmit(true, true, true, true);
        emit Divest(400 * _1_USDCE);

        uint256 divestAssets = vault.divestSingleDirectSingleVault(address(yUsdce), sharesToDivest, minAssetsOut);

        assertGt(divestAssets, 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), 0);
    }

    function test_MetaVault_divestSingleDirectMultiVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        MockERC4626 smUsdce = new MockERC4626(USDCE_BASE, "Sommelier USDCE", "smUSDCe", true, 0);

        oracle.setValues(baseChainId, address(yUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });
        oracle.setValues(baseChainId, address(smUsdce), _1_USDCE, block.timestamp, USDCE_BASE, users.alice, 6);
        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(smUsdce),
            vaultDecimals: smUsdce.decimals(),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 amountPerVault = 400 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(smUsdce);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = smUsdce.previewDeposit(amountPerVault);

        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        address[] memory divestVaults = new address[](2);
        divestVaults[0] = address(yUsdce);
        divestVaults[1] = address(smUsdce);

        uint256[] memory divestShares = new uint256[](2);
        divestShares[0] = yUsdce.balanceOf(address(vault));
        divestShares[1] = smUsdce.balanceOf(address(vault));

        uint256[] memory minDivestAmounts = new uint256[](2);
        minDivestAmounts[0] = yUsdce.convertToAssets(divestShares[0]);
        minDivestAmounts[1] = smUsdce.convertToAssets(divestShares[1]);

        uint256[] memory divestAssets = vault.divestSingleDirectMultiVault(divestVaults, divestShares, minDivestAmounts);

        assertEq(divestAssets.length, 2);
        assertGt(divestAssets[0], 0);
        assertGt(divestAssets[1], 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
    }

    function test_MetaVault_divestSingleXChainSingleVault() public {
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

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        uint256 value = _getDivestSingleXChainSingleVaultValue(superformId, investAmount);

        SingleXChainSingleVaultStateReq memory divestReq =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress);
        uint256 lastSharePrice = report.sharePrice;
        uint256 expectedDivestedValue = lastSharePrice * shares / 10 ** 6;

        console2.log("expectedDivestedValue : %s", expectedDivestedValue);

        divestReq.superformData.outputAmount = expectedDivestedValue;

        uint256 expectedDivestedValueT = 61_574_985;

        vm.expectEmit(true, true, true, true);
        emit Divest(expectedDivestedValueT);

        vm.startPrank(users.alice);
        vault.divestSingleXChainSingleVault{ value: value }(divestReq);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 938_424_882);
        assertEq(gateway.totalPendingXChainDivests(), expectedDivestedValueT);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        deal(USDCE_BASE, gateway.getReceiver(requestId), expectedDivestedValue);
        gateway.settleDivest(requestId, 0, false);

        assertEq(vault.totalAssets(), 1_538_424_749);
        assertEq(vault.totalWithdrawableAssets(), 1_538_424_749);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_divestSingleXChainSingleVault_revert_InvalidSuperformId() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
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
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        SingleVaultSFData memory superformData;
        superformData.superformId = 0;
        superformData.amount = 600 * _1_USDCE;
        superformData.maxSlippage = 0;
        superformData.hasDstSwap = false;
        superformData.retain4626 = false;

        SingleXChainSingleVaultStateReq memory req;
        req.dstChainId = optimismChainId;
        req.superformData = superformData;
        req.ambIds = new uint8[](1);
        req.ambIds[0] = 1;

        vm.expectRevert(abi.encodeWithSignature("InvalidSuperformId()"));
        vault.divestSingleXChainSingleVault(req);
    }

    function test_MetaVault_divestSingleXChainSingleVault_revert_VaultNotListed() public {
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
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        SingleXChainSingleVaultStateReq memory req =
            _buildDivestSingleXChainSingleVaultParams(superformId, 600 * _1_USDCE);

        vm.expectRevert(abi.encodeWithSignature("VaultNotListed()"));
        vault.divestSingleXChainSingleVault(req);
    }

    function test_MetaVault_divestSingleXChainSingleVault_revert_InvalidAmount() public {
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

        SingleVaultSFData memory superformData;
        superformData.superformId = superformId;
        superformData.amount = 0;
        superformData.maxSlippage = 0;
        superformData.hasDstSwap = false;
        superformData.retain4626 = false;

        SingleXChainSingleVaultStateReq memory req;
        req.dstChainId = optimismChainId;
        req.superformData = superformData;
        req.ambIds = new uint8[](1);
        req.ambIds[0] = 1;

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.divestSingleXChainSingleVault(req);
    }

    function test_MetaVault_divestSingleXChainSingleVault_revert_Unauthorized() public {
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

        SingleXChainSingleVaultStateReq memory req =
            _buildDivestSingleXChainSingleVaultParams(superformId, 600 * _1_USDCE);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestSingleXChainSingleVault(req, false);
    }

    function test_MetaVault_divestSingleXChainSingleVault_failed() public {
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

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        uint256 value = _getDivestSingleXChainSingleVaultValue(superformId, investAmount);

        SingleXChainSingleVaultStateReq memory divestReq =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress);
        uint256 lastSharePrice = report.sharePrice;
        uint256 expectedDivestedValue = lastSharePrice * shares / 10 ** 6;
        divestReq.superformData.outputAmount = expectedDivestedValue;

        uint256 expected = 61_574_985;

        vm.expectEmit(true, true, true, true);
        emit Divest(expected);

        vm.startPrank(users.alice);
        vault.divestSingleXChainSingleVault{ value: value }(divestReq);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 938_424_882);
        assertEq(gateway.totalPendingXChainDivests(), expected);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        address receiver = gateway.getReceiver(requestId);
        _mintSuperpositions(receiver, superformId, shares);

        assertEq(config.superPositions.balanceOf(address(vault), superformId), 1_078_517_421);
        (,,,, uint128 vaultDebt,) = vault.vaults(superformId);
        assertEq(vaultDebt, 599_999_867);
        assertEq(vault.totalDebt(), vaultDebt);
        assertEq(vault.totalXChainAssets(), 1_138_424_749);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_divestSingleXChainMultiVault() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );
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
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        uint256 investAmount = 1200 * _1_USDCE;

        SingleXChainMultiVaultStateReq memory investReq =
            _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        investReq.superformsData.amounts[0] = 600 * _1_USDCE;
        investReq.superformsData.amounts[1] = 600 * _1_USDCE;

        uint256 shares_usdc = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares_aloe = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, amounts[1]);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investSingleXChainMultiVault{ value: nativeValue }(investReq);
        vm.stopPrank();

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares_usdc);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares_aloe);

        SingleXChainMultiVaultStateReq memory divestReq =
            _buildDivestSingleXChainMultiVaultParams(superformIds, amounts);
        divestReq.superformsData.amounts[0] = shares_usdc;
        divestReq.superformsData.amounts[1] = shares_aloe;
        VaultReport memory report_usdc = oracle.getReport(optimismChainId, vaultAddress_usdc);
        VaultReport memory report_aloe = oracle.getReport(optimismChainId, vaultAddress_usdc_aloe_op);

        uint256 expectedValue_usdc = report_usdc.sharePrice * shares_usdc / 10 ** 6;
        uint256 expectedValue_aloe = report_aloe.sharePrice * shares_aloe / 10 ** 6;
        uint256 totalExpectedValue = expectedValue_usdc + expectedValue_aloe;

        divestReq.superformsData.outputAmounts[0] = expectedValue_usdc;
        divestReq.superformsData.outputAmounts[1] = expectedValue_aloe;

        uint256 nativeValue2 = multiVaultWithdrawValues[multiVaultKey];

        vm.expectEmit(true, true, true, true);
        emit Divest(totalExpectedValue);

        vm.startPrank(users.alice);
        vault.divestSingleXChainMultiVault{ value: nativeValue2 }(divestReq);

        assertEq(vault.totalAssets(), 800 * _1_USDCE + totalExpectedValue);
        assertEq(vault.totalWithdrawableAssets(), 800 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), totalExpectedValue);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        deal(USDCE_BASE, gateway.getReceiver(requestId), totalExpectedValue);
        gateway.settleDivest(requestId, 0, false);

        assertEq(vault.totalAssets(), 800 * _1_USDCE + totalExpectedValue);
        assertEq(vault.totalWithdrawableAssets(), totalExpectedValue + 800 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_divestSingleXChainMultiVault_revert_InvalidAmount() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;

        uint32 optimismChainId = 10;

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

        MultiVaultSFData memory superformsData;
        superformsData.superformIds = new uint256[](0);
        superformsData.amounts = new uint256[](0);
        superformsData.outputAmounts = new uint256[](0);
        superformsData.maxSlippages = new uint256[](0);
        superformsData.hasDstSwaps = new bool[](0);
        superformsData.retain4626s = new bool[](0);

        SingleXChainMultiVaultStateReq memory req;
        req.dstChainId = optimismChainId;
        req.superformsData = superformsData;
        req.ambIds = new uint8[](1);
        req.ambIds[0] = 1;

        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestSingleXChainMultiVault(req, false);
    }

    function test_MetaVault_divestSingleXChainMultiVault_revert_TotalAmountMismatch() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;

        uint32 optimismChainId = 10;

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

        MultiVaultSFData memory superformsData;
        superformsData.superformIds = new uint256[](2);
        superformsData.superformIds[0] = superformId_usdc;
        superformsData.superformIds[1] = superformId_usdc_aloe_op;

        superformsData.amounts = new uint256[](1);
        superformsData.amounts[0] = 600 * _1_USDCE;

        superformsData.outputAmounts = new uint256[](2);
        superformsData.maxSlippages = new uint256[](2);
        superformsData.hasDstSwaps = new bool[](2);
        superformsData.retain4626s = new bool[](2);

        SingleXChainMultiVaultStateReq memory req;
        req.dstChainId = optimismChainId;
        req.superformsData = superformsData;
        req.ambIds = new uint8[](1);
        req.ambIds[0] = 1;

        vm.expectRevert(abi.encodeWithSignature("TotalAmountMismatch()"));
        vault.divestSingleXChainMultiVault(req);
    }

    function test_MetaVault_divestMultiXChainSingleVault() public {
        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
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

        MultiDstSingleVaultStateReq memory divestReq = _buildDivestMultiXChainSingleVaultParams(superformIds, amounts);

        divestReq.superformsData[0].amount = shares;
        divestReq.superformsData[1].amount = shares2;

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress_usdc_optimisim);
        uint256 lastSharePrice = report.sharePrice;

        VaultReport memory report2 = oracle.getReport(polygonChainId, vaultAddress_usdc_pol);
        uint256 lastSharePrice2 = report2.sharePrice;

        uint256 expectedDivestValuePol = lastSharePrice2 * shares2 / 10 ** 6;
        uint256 expectedDivestValueOptimism = lastSharePrice * shares / 10 ** 6;

        uint256 expectedDivestedValue = expectedDivestValuePol + expectedDivestValueOptimism;

        divestReq.superformsData[0].outputAmount = expectedDivestValuePol; // EXACTLY
        divestReq.superformsData[1].outputAmount = expectedDivestValueOptimism; // ALOE

        // //Execute divest
        vm.expectEmit(true, true, true, true);
        emit Divest(expectedDivestedValue);
        bytes32 multiVaultKeyWithdraw = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValueWithdraw = multiChainWithdrawValues[multiVaultKeyWithdraw];

        vm.startPrank(users.alice);

        vault.divestMultiXChainSingleVault{ value: nativeValueWithdraw }(divestReq);

        assertEq(vault.totalAssets(), expectedDivestedValue + 800_000_000);
        assertEq(vault.totalWithdrawableAssets(), 800_000_000);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        bytes32 requestId2 = gateway.getRequestsQueue()[1];

        deal(USDCE_BASE, gateway.getReceiver(requestId), expectedDivestValuePol);
        gateway.settleDivest(requestId, 0, false);

        deal(USDCE_BASE, gateway.getReceiver(requestId2), expectedDivestValueOptimism);
        gateway.settleDivest(requestId2, 0, false);

        assertEq(vault.totalAssets(), expectedDivestedValue + 800_000_000);
        assertEq(vault.totalWithdrawableAssets(), expectedDivestedValue + 800_000_000);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_divestMultiXChainSingleVault_revert_InvalidAmount() public {
        // Setup vaults and oracles
        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;
        uint32 optimismChainId = 10;
        uint64 polygonChainId = 137;

        // Add vaults
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

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        // Create request with zero amount
        MultiDstSingleVaultStateReq memory req;
        req.dstChainIds = new uint64[](2);
        req.dstChainIds[0] = optimismChainId;
        req.dstChainIds[1] = polygonChainId;

        req.superformsData = new SingleVaultSFData[](2);
        req.superformsData[0].superformId = superformId_usdc_optimisim;
        req.superformsData[0].amount = 0; // Invalid zero amount
        req.superformsData[1].superformId = superformId_usdc_pol;
        req.superformsData[1].amount = 0;

        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestMultiXChainSingleVault(req, false);
    }

    function test_MetaVault_divestMultiXChainSingleVault_revert_Unauthorized() public {
        // Setup vaults and oracles
        address vaultAddress_usdc_optimisim = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_optimisim = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

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

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        MultiDstSingleVaultStateReq memory req;
        req.dstChainIds = new uint64[](1);
        req.dstChainIds[0] = optimismChainId;

        req.superformsData = new SingleVaultSFData[](1);
        req.superformsData[0].superformId = superformId_usdc_optimisim;
        req.superformsData[0].amount = 100 * _1_USDCE;

        // Try to call from unauthorized address
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestMultiXChainSingleVault(req, false);
        vm.stopPrank();
    }

    function test_MetaVault_divestMultiXChainMultiVault() public {
        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc_pol = AAVE_USDC_VAULT_ID_POLYGON;

        uint32 optimismChainId = 10;
        uint32 polygonChainId = 137;

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

        uint256[] memory superformIds = new uint256[](3);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;
        superformIds[2] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;
        amounts[2] = 600 * _1_USDCE;

        uint256 investAmount = 1800 * _1_USDCE;
        (MultiDstMultiVaultStateReq memory req) = _buildInvestMultiXChainMultiVaultParams(superformIds, amounts);

        req.superformsData[0].amounts[0] = 600 * _1_USDCE;
        req.superformsData[0].amounts[1] = 600 * _1_USDCE;
        req.superformsData[1].amounts[0] = 600 * _1_USDCE;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress_usdc, req.superformsData[0].amounts[0]);
        uint256 shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, req.superformsData[1].amounts[0]);
        uint256 shares3 = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, req.superformsData[0].amounts[1]);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiChainMultiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investMultiXChainMultiVault{ value: nativeValue }(req);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares3);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        MultiDstMultiVaultStateReq memory divestReq = _buildDivestMultiXChainMultiVaultParams(superformIds, amounts);

        divestReq.superformsData[0].amounts[0] = shares;
        divestReq.superformsData[1].amounts[0] = shares2;
        divestReq.superformsData[0].amounts[1] = shares3;

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress_usdc);
        uint256 lastSharePrice = report.sharePrice;

        VaultReport memory report2 = oracle.getReport(polygonChainId, vaultAddress_usdc_pol);
        uint256 lastSharePrice2 = report2.sharePrice;

        VaultReport memory report3 = oracle.getReport(optimismChainId, vaultAddress_usdc_aloe_op);
        uint256 lastSharePrice3 = report3.sharePrice;

        uint256 expectedDivestedValue = lastSharePrice * shares / 10 ** 6 + lastSharePrice2 * shares2 / 10 ** 6
            + lastSharePrice3 * shares3 / 10 ** 6;

        uint256 expectedOptimismValue = lastSharePrice * shares / 10 ** 6 + lastSharePrice3 * shares3 / 10 ** 6; // EXACTLY
            // + ALOE vaults
            // + ALOE vaults
        uint256 expectedPolygonValue = lastSharePrice2 * shares2 / 10 ** 6;

        divestReq.superformsData[0].outputAmounts[0] = expectedOptimismValue / 2; // EXACTLY
        divestReq.superformsData[0].outputAmounts[1] = expectedOptimismValue / 2; // ALOE
        divestReq.superformsData[1].outputAmounts[0] = expectedPolygonValue;

        // //Execute divest
        vm.expectEmit(true, true, true, true);
        emit Divest(expectedDivestedValue);

        uint256 nativeValueWithdraw = multiChainMultiVaultWithdrawValues[multiVaultKey];

        vm.startPrank(users.alice);

        vault.divestMultiXChainMultiVault{ value: nativeValueWithdraw }(divestReq);

        assertEq(vault.totalAssets(), expectedDivestedValue + 200 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 200_000_000);
        assertEq(gateway.totalPendingXChainDivests(), expectedDivestedValue);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        bytes32 requestId2 = gateway.getRequestsQueue()[1];

        deal(USDCE_BASE, gateway.getReceiver(requestId), expectedOptimismValue);
        gateway.settleDivest(requestId, 0, false);

        deal(USDCE_BASE, gateway.getReceiver(requestId2), expectedPolygonValue);
        gateway.settleDivest(requestId2, 0, false);

        assertEq(vault.totalAssets(), expectedDivestedValue + 200 * _1_USDCE);

        assertEq(vault.totalWithdrawableAssets(), expectedDivestedValue + 200 * _1_USDCE);

        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_divestMultiXChainMultiVault_revert_InvalidAmount() public {
        // Setup vaults and oracles
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        // Add vaults
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

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        // Create request with zero amounts
        MultiDstMultiVaultStateReq memory req;
        req.dstChainIds = new uint64[](1);
        req.dstChainIds[0] = optimismChainId;

        req.superformsData = new MultiVaultSFData[](1);
        req.superformsData[0].superformIds = new uint256[](2);
        req.superformsData[0].superformIds[0] = superformId_usdc;
        req.superformsData[0].superformIds[1] = superformId_usdc_aloe_op;

        req.superformsData[0].amounts = new uint256[](2);
        req.superformsData[0].amounts[0] = 0; // Invalid zero amount
        req.superformsData[0].amounts[1] = 0;

        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestMultiXChainMultiVault(req, false);
    }

    function test_MetaVault_divestMultiXChainMultiVault_revert_Unauthorized() public {
        // Setup vaults and oracles
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

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

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        MultiDstMultiVaultStateReq memory req;
        req.dstChainIds = new uint64[](1);
        req.dstChainIds[0] = optimismChainId;

        req.superformsData = new MultiVaultSFData[](1);
        req.superformsData[0].superformIds = new uint256[](1);
        req.superformsData[0].superformIds[0] = superformId_usdc;

        req.superformsData[0].amounts = new uint256[](1);
        req.superformsData[0].amounts[0] = 100 * _1_USDCE;

        // Try to call from unauthorized address
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.divestMultiXChainMultiVault(req, false);
        vm.stopPrank();
    }

    function test_MetaVault_emergencyDivest_after_xchain_invest() public {
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

        investReq.superformData.amount = 600 * _1_USDCE;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);
        uint256 value = _getDivestSingleXChainSingleVaultValue(superformId, investAmount);
        SingleXChainSingleVaultStateReq memory req =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        VaultReport memory report = oracle.getReport(optimismChainId, vaultAddress);
        uint256 expectedDivestedValue = report.sharePrice * shares / 10 ** 6;
        req.superformData.amount = shares;
        vm.startPrank(users.alice);

        req.superformData.outputAmount = expectedDivestedValue;

        vault.emergencyDivestSingleXChainSingleVault{ value: value }(req);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        deal(USDCE_BASE, gateway.getReceiver(requestId), expectedDivestedValue);
        gateway.settleDivest(requestId, expectedDivestedValue, false);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_onERC1155BatchReceived() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;

        address vaultAddress_usdc_aloe_op = AVVE_USDC_VAULT_OPTIMISM;
        uint256 superformId_usdc_aloe_op = AVVE_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc,
            _getSharePrice(optimismChainId, vaultAddress_usdc),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );

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
            superformId: superformId_usdc,
            vault: vaultAddress_usdc,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc),
            oracle: ISharePriceOracle(address(oracle))
        });

        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId_usdc_aloe_op,
            vault: vaultAddress_usdc_aloe_op,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress_usdc_aloe_op),
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        SingleXChainMultiVaultStateReq memory investReq =
            _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        investReq.superformsData.amounts[0] = amounts[0];
        investReq.superformsData.amounts[1] = amounts[1];

        uint256 shares_usdc = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares_aloe = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, amounts[1]);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investSingleXChainMultiVault{ value: nativeValue }(investReq);
        vm.stopPrank();

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares_usdc);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares_aloe);

        SingleXChainMultiVaultStateReq memory divestReq =
            _buildDivestSingleXChainMultiVaultParams(superformIds, amounts);

        divestReq.superformsData.amounts[0] = shares_usdc;
        divestReq.superformsData.amounts[1] = shares_aloe;

        VaultReport memory report_usdc = oracle.getReport(optimismChainId, vaultAddress_usdc);
        VaultReport memory report_aloe = oracle.getReport(optimismChainId, vaultAddress_usdc_aloe_op);

        uint256 expectedValue_usdc = report_usdc.sharePrice * shares_usdc / 10 ** 6;
        uint256 expectedValue_aloe = report_aloe.sharePrice * shares_aloe / 10 ** 6;
        uint256 totalExpectedValue = expectedValue_usdc + expectedValue_aloe;

        divestReq.superformsData.outputAmounts[0] = expectedValue_usdc;
        divestReq.superformsData.outputAmounts[1] = expectedValue_aloe;

        uint256 nativeValue2 = multiVaultWithdrawValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.divestSingleXChainMultiVault{ value: nativeValue2 }(divestReq);

        assertEq(vault.totalAssets(), totalExpectedValue + 800 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 800 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), totalExpectedValue);

        bytes32 requestId = gateway.getRequestsQueue()[0];
        address receiver = gateway.getReceiver(requestId);

        deal(USDCE_BASE, receiver, totalExpectedValue);
        gateway.settleDivest(requestId, 0, false);

        assertEq(vault.totalAssets(), totalExpectedValue + 800 * _1_USDCE);

        assertEq(vault.totalWithdrawableAssets(), totalExpectedValue + 800 * _1_USDCE);

        assertEq(gateway.totalPendingXChainDivests(), 0);
    }
}
