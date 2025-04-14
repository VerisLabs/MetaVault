// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BaseVaultTest, IMetaVault } from "../base/BaseVaultTest.t.sol";

import { ERC4626Events } from "../helpers/ERC4626Events.sol";
import { ERC7540Events } from "../helpers/ERC7540Events.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";
import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { ERC7540 } from "lib/Lib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MetaVault } from "src/MetaVault.sol";

import "src/helpers/AddressBook.sol";

import {
    IBaseRouter as ISuperformRouter,
    ISuperPositions,
    ISuperformFactory,
    ISuperformGateway
} from "src/interfaces/Lib.sol";
import {
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultWithdraw
} from "src/types/Lib.sol";

import { ERC7540Engine, MetaVaultAdmin } from "modules/Lib.sol";

contract ERC7540PropertiesTest is BaseVaultTest, ERC7540Events, ERC4626Events {
    using SafeTransferLib for address;

    ISuperPositions superPositions;
    ISuperformRouter vaultRouter;
    ISuperformFactory factory;
    uint24 sharesLockTime = 30 days;
    address treasury = makeAddr("treasury");
    ERC7540Engine engine;
    MetaVaultAdmin admin;

    function setUp() public {
        super._setUp("POLYGON", 68_186_888);
        superPositions = ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON);
        vaultRouter = ISuperformRouter(SUPERFORM_ROUTER_POLYGON);
        factory = ISuperformFactory(SUPERFORM_FACTORY_POLYGON);
        config = polygonUsdceVaultConfig();
        vault = IMetaVault(address(new MetaVault(config)));
        admin = new MetaVaultAdmin();
        vault.addFunctions(admin.selectors(), address(admin), false);
        ISuperformGateway gateway = deployGatewayPolygon(address(vault), users.alice);
        vault.setGateway(address(gateway));
        engine = new ERC7540Engine();
        vault.addFunctions(engine.selectors(), address(engine), false);
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
    }

    function test_erc7540_requestDeposit() public {
        uint256 amount = 100 * _1_USDCE;
        vm.expectEmit();
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vault.requestDeposit(amount, users.alice, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 100 * _1_USDCE);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(users.alice), 0);
    }

    function test_revert_erc7540_requestDeposit_zeroAssets() public {
        vm.expectRevert(ERC7540.InvalidZeroAssets.selector);
        vault.requestDeposit(0, users.alice, users.alice);
    }

    function test_erc7540_deposit() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        vm.expectEmit();
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 shares = vault.deposit(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(shares, amount);
        assertEq(vault.balanceOf(users.alice), shares);
    }

    function test_revert_erc7540_deposit_noRequest() public {
        uint256 amount = 100 * _1_USDCE;
        vm.expectRevert(ERC4626.DepositMoreThanMax.selector);
        vault.deposit(amount, users.alice);
    }

    function test_erc7540_mint() public {
        uint256 amount = 100 * _1_USDCE;

        vault.requestDeposit(amount, users.alice, users.alice);

        vm.expectEmit();
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 assets = vault.mint(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(assets, amount);
        assertEq(vault.balanceOf(users.alice), assets);
    }

    function test_revert_erc7540_mint_noRequest() public {
        uint256 amount = 100 * _1_USDCE;
        vm.expectRevert(ERC4626.MintMoreThanMax.selector);
        vault.mint(amount, users.alice);
    }

    function test_erc7540_requestRedeem_sharesLocked() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        vm.expectRevert(MetaVault.SharesLocked.selector);
        vault.requestRedeem(shares, users.alice, users.alice);
    }

    function test_erc7540_requestRedeem() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        shares;
        skip(config.sharesLockTime);
        vm.expectEmit();
        emit RedeemRequest(users.alice, users.alice, 0, users.alice, shares);

        vault.requestRedeem(shares, users.alice, users.alice);
        assertEq(vault.balanceOf(address(vault)), shares);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(vault.pendingRedeemRequest(users.alice), shares);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), amount);
        assertEq(vault.totalAssets(), amount);

        _processRedeemRequest(users.alice);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), amount);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_revert_erc7540_requestRedeem_zeroShares() public {
        vm.expectRevert(ERC7540.InvalidZeroShares.selector);
        vault.requestRedeem(0, users.alice, users.alice);
    }

    function test_erc7540_redeem() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        shares;
        skip(config.sharesLockTime);

        vault.requestRedeem(shares, users.alice, users.alice);
        _processRedeemRequest(users.alice);

        uint256 balanceBefore = USDCE_POLYGON.balanceOf(users.alice);
        vm.expectEmit();
        emit Withdraw(users.alice, users.alice, users.alice, amount, shares);
        uint256 assets = vault.redeem(shares, users.alice, users.alice);
        uint256 balanceAfter = USDCE_POLYGON.balanceOf(users.alice);
        assertEq(assets, amount);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_revert_erc7540_redeem_noRequest() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);

        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        vault.redeem(shares, users.alice, users.alice);
    }

    function test_erc7540_withdraw() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        shares;
        skip(config.sharesLockTime);

        vault.requestRedeem(shares, users.alice, users.alice);
        _processRedeemRequest(users.alice);

        uint256 balanceBefore = USDCE_POLYGON.balanceOf(users.alice);
        vm.expectEmit();
        emit Withdraw(users.alice, users.alice, users.alice, amount, shares);
        uint256 burntShares = vault.withdraw(amount, users.alice, users.alice);
        uint256 balanceAfter = USDCE_POLYGON.balanceOf(users.alice);
        assertEq(burntShares, shares);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_revert_erc7540_withdraw_noRequest() public {
        uint256 amount = 100 * _1_USDCE;

        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        vault.withdraw(amount, users.alice, users.alice);
    }

    function _processRedeemRequest(address user) internal {
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(ProcessRedeemRequestParams(user, 0, sXsV, sXmV, mXsV, mXmV));
    }
}
