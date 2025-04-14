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
import { AssetsManager, ERC7540Engine, MetaVaultAdmin } from "modules/Lib.sol";

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

contract MetaVaultInvestTest is BaseVaultTest, SuperformActions, MetaVaultEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    AssetsManager manager;
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

    function test_MetaVault_investSingleDirectSingleVault() public {
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

        vm.expectRevert(AssetsManager.InsufficientAssets.selector);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview + 1);

        vm.expectEmit(true, true, true, true);
        emit Invest(400 * _1_USDCE);
        uint256 shares = vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        assertEq(shares, depositPreview);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 600 * _1_USDCE);
        assertEq(vault.totalDebt(), 400 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), depositPreview);
    }

    function test_MetaVault_investSingleDirectMultiVault() public {
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

        uint256 amountPerVault = 500 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(smUsdce);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = smUsdce.previewDeposit(amountPerVault);

        minAmountsOut[1] += 1;

        vm.expectRevert(AssetsManager.InsufficientAssets.selector);
        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        minAmountsOut[1] -= 1;

        vm.expectEmit(true, true, true, true);
        emit Invest(500 * _1_USDCE);
        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);
        assertApproxEq(vault.totalAssets(), 1000 * _1_USDCE, 5);
        assertEq(vault.totalIdle(), 0 * _1_USDCE);
        assertEq(vault.totalDebt(), 1000 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), minAmountsOut[0]);
        assertEq(smUsdce.balanceOf(address(vault)), minAmountsOut[1]);
    }

    function test_MetaVault_investSingleXChainSingleVault() public {
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

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );
        assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);
        assertEq(vault.totalAssets(), 999_999_867);
        assertEq(vault.totalWithdrawableAssets(), 999_999_867);
        assertEq(vault.totalXChainAssets(), 599_999_867);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalIdle(), 400 * _1_USDCE);
        assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
    }

    function test_MetaVault_investSingleXChainSingleVault_revert_VaultNotListed() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint32 optimismChainId = 10;

        oracle.setValues(
            optimismChainId,
            vaultAddress,
            _getSharePrice(optimismChainId, vaultAddress),
            block.timestamp,
            USDCE_BASE,
            users.alice,
            6
        );

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 investAmount = 600 * _1_USDCE;

        SingleXChainSingleVaultStateReq memory req =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);
        vm.expectRevert(abi.encodeWithSignature("VaultNotListed()"));
        vault.investSingleXChainSingleVault(req);
    }

    function test_MetaVault_investSingleXChainSingleVault_revert_Unauthorized() public {
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

        SingleXChainSingleVaultStateReq memory req =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.investSingleXChainSingleVault(req);
    }

    function test_MetaVault_investSingleXChainMultiVault() public {
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

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;
        SingleXChainMultiVaultStateReq memory req = _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        req.superformsData.amounts[0] = 600 * _1_USDCE;
        req.superformsData.amounts[1] = 600 * _1_USDCE;

        uint256 shares_usdc = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares_usdcA = _previewDeposit(optimismChainId, vaultAddress_usdc_aloe_op, amounts[1]);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiVaultDepositValues[multiVaultKey];

        vm.startPrank(users.alice);
        vault.investSingleXChainMultiVault{ value: nativeValue }(req);

        assertEq(USDCE_BASE.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), 1200 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 0 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 0 * _1_USDCE);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares_usdc);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares_usdcA);

        assertEq(vault.totalAssets(), 1_199_999_755);
        assertEq(vault.totalWithdrawableAssets(), 1_199_999_755);
        assertEq(vault.totalXChainAssets(), 1_199_999_755);
        assertEq(vault.totalLocalAssets(), 0 * _1_USDCE);
        assertEq(vault.totalIdle(), 0 * _1_USDCE);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc), shares_usdc);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc_aloe_op), shares_usdcA);
    }

    function test_MetaVault_investMultiXChainSingleVault() public {
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
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        MultiDstSingleVaultStateReq memory req = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress_usdc, amounts[0]);
        uint256 shares2 = _previewDeposit(polygonChainId, vaultAddress_usdc_pol, amounts[1]);

        vm.expectEmit(true, true, true, true);
        emit Invest(1200 * _1_USDCE);

        bytes32 multiVaultKey = _getMultiVaultPayloadKey(superformIds, amounts);
        uint256 nativeValue = multiChainDepositValues[multiVaultKey];

        vm.startPrank(users.alice);

        vault.investMultiXChainSingleVault{ value: nativeValue }(req);

        assertEq(USDCE_BASE.balanceOf(address(vault)), 800 * _1_USDCE);
        assertEq(vault.totalAssets(), 2000 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 800 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 800 * _1_USDCE);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);

        assertApproxEq(vault.totalAssets(), 2000 * _1_USDCE, 500);
        assertApproxEq(vault.totalWithdrawableAssets(), 2000 * _1_USDCE, 500);
        assertApproxEq(vault.totalXChainAssets(), 1200 * _1_USDCE, 500);
        assertEq(vault.totalLocalAssets(), 800 * _1_USDCE);
        assertEq(vault.totalIdle(), 800 * _1_USDCE);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc), shares);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc_pol), shares2);
    }

    function test_MetaVault_investMultiXChainMultiVault() public {
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

        assertEq(USDCE_BASE.balanceOf(address(vault)), 200_000_000);
        assertEq(vault.totalAssets(), 2000 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 200_000_000);
        assertEq(vault.totalWithdrawableAssets(), 200_000_000);

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc, shares);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_pol, shares2);
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId_usdc_aloe_op, shares3);

        assertEq(vault.totalAssets(), 1_999_999_461);
        assertEq(vault.totalWithdrawableAssets(), 1_999_999_461);
        assertEq(vault.totalXChainAssets(), 1_799_999_461);
        assertEq(vault.totalLocalAssets(), 200_000_000);
        assertEq(vault.totalIdle(), 200_000_000);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc), shares);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc_pol), shares2);
        assertEq(config.superPositions.balanceOf(address(vault), superformId_usdc_aloe_op), shares3);
    }

    function test_MetaVault_investSingleXChainMultiVault_revert_InvalidAmount() public {
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

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.investSingleXChainMultiVault(req);
    }

    function test_MetaVault_investSingleXChainMultiVault_revert_TotalAmountMismatch() public {
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
        vault.investSingleXChainMultiVault(req);
    }

    function test_MetaVault_investSingleXChainMultiVault_revert_VaultNotListed() public {
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

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        (SingleXChainMultiVaultStateReq memory req) = _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        vm.expectRevert(abi.encodeWithSignature("VaultNotListed()"));
        vault.investSingleXChainMultiVault(req);
    }

    function test_MetaVault_investSingleXChainMultiVault_revert_Unauthorized() public {
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

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        SingleXChainMultiVaultStateReq memory req = _buildInvestSingleXChainMultiVaultParams(superformIds, amounts);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.investSingleXChainMultiVault(req);
    }

    function test_MetaVault_investMultiXChainSingleVault_revert_InvalidAmount() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;

        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
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

        MultiDstSingleVaultStateReq memory req;
        req.superformsData = new SingleVaultSFData[](0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.investMultiXChainSingleVault(req);
    }

    function test_MetaVault_investMultiXChainSingleVault_revert_VaultNotListed() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
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

        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        MultiDstSingleVaultStateReq memory req = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        vm.expectRevert(abi.encodeWithSignature("VaultNotListed()"));
        vault.investMultiXChainSingleVault(req);
    }

    function test_MetaVault_investMultiXChainSingleVault_revert_Unauthorized() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
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

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;

        MultiDstSingleVaultStateReq memory req = _buildInvestMultiXChainSingleVaultParams(superformIds, amounts);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.investMultiXChainSingleVault(req);
    }

    function test_MetaVault_investMultiXChainMultiVault_revert_InvalidAmount() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
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

        MultiDstMultiVaultStateReq memory req;
        req.superformsData = new MultiVaultSFData[](0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.investMultiXChainMultiVault(req);
    }

    function test_MetaVault_investMultiXChainMultiVault_revert_TotalAmountMismatch() public {
        address vaultAddress_usdc = EXACTLY_USDC_VAULT_OPTIMISM;
        address vaultAddress_usdc_pol = AAVE_USDC_VAULT_POLYGON;
        uint256 superformId_usdc = EXACTLY_USDC_VAULT_ID_OPTIMISM;
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

        _depositAtomic(1200 * _1_USDCE, users.alice, users.alice);

        MultiDstMultiVaultStateReq memory req;
        req.superformsData = new MultiVaultSFData[](1);
        req.superformsData[0].superformIds = new uint256[](2);
        req.superformsData[0].superformIds[0] = superformId_usdc;
        req.superformsData[0].superformIds[1] = superformId_usdc_pol;

        req.superformsData[0].amounts = new uint256[](1);
        req.superformsData[0].amounts[0] = 600 * _1_USDCE;

        vm.expectRevert(abi.encodeWithSignature("TotalAmountMismatch()"));
        vault.investMultiXChainMultiVault(req);
    }

    function test_MetaVault_investMultiXChainMultiVault_revert_VaultNotListed() public {
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

        oracle.setValues(
            optimismChainId,
            vaultAddress_usdc_aloe_op,
            _getSharePrice(optimismChainId, vaultAddress_usdc_aloe_op),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );

        oracle.setValues(
            polygonChainId,
            vaultAddress_usdc_pol,
            _getSharePrice(polygonChainId, vaultAddress_usdc_pol),
            block.timestamp,
            USDCE_BASE,
            users.bob,
            6
        );

        _depositAtomic(2000 * _1_USDCE, users.alice, users.alice);

        uint256[] memory superformIds = new uint256[](3);
        superformIds[0] = superformId_usdc;
        superformIds[1] = superformId_usdc_pol;
        superformIds[2] = superformId_usdc_aloe_op;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 600 * _1_USDCE;
        amounts[1] = 600 * _1_USDCE;
        amounts[2] = 600 * _1_USDCE;

        MultiDstMultiVaultStateReq memory req = _buildInvestMultiXChainMultiVaultParams(superformIds, amounts);

        vm.expectRevert(abi.encodeWithSignature("VaultNotListed()"));
        vault.investMultiXChainMultiVault(req);
    }

    function test_MetaVault_investMultiXChainMultiVault_revert_Unauthorized() public {
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

        MultiDstMultiVaultStateReq memory req = _buildInvestMultiXChainMultiVaultParams(superformIds, amounts);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        gateway.investMultiXChainMultiVault(req);
    }
}
