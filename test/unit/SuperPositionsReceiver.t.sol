// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SuperPositionsReceiverWrapper } from "../helpers/mock/SuperPositionsReceiverWrapper.sol";
import { IERC1155A } from "src/interfaces/IERC1155A.sol";

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MetaVaultAdmin } from "src/modules/Lib.sol";

import { SuperPositionsReceiverEvents } from "../helpers/SuperPositionsReceiverEvents.sol";
import { DAI_BASE, USDCE_BASE, _1_USDCE } from "../helpers/Tokens.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { IMetaVault, ISuperPositionsReceiver, ISuperformGateway } from "interfaces/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import {
    MockBridgeTarget, MockBridgeTargetNoTransfer, MockFailureBridgeTarget
} from "../helpers/mock/MockBridgeTarget.sol";
import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { MetaVault } from "src/MetaVault.sol";

import { SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "src/helpers/AddressBook.sol";

import { SuperPositionsReceiver } from "src/crosschain/SuperPositionsReceiver.sol";

contract SuperPositionsReceiverTest is BaseVaultTest, SuperPositionsReceiverEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    ISuperformGateway public gateway;
    uint32 baseChainId = 137; // polygon
    uint32 destiChainId = 8453; // base
    MetaVaultAdmin admin;

    ISuperPositionsReceiver superPositionsReceiver;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        config.signerRelayer = relayer;
        vault = IMetaVault(address(new MetaVaultWrapper(config)));
        admin = new MetaVaultAdmin();
        vault.addFunctions(admin.selectors(), address(admin), false);
        gateway = deployGatewayBase(address(vault), users.alice);
        vault.setGateway(address(gateway));
        gateway.grantRoles(users.alice, gateway.RELAYER_ROLE());

        console2.log("vault address : %s", address(vault));
        console2.log("recovery address : %s", gateway.recoveryAddress());
    }

    function _setupContractLabels() private {
        vm.label(SUPERFORM_SUPERPOSITIONS_BASE, "SuperPositions");
        vm.label(address(vault), "MetaVault");
        vm.label(USDCE_BASE, "USDC");
    }

    function setUp() public {
        super._setUp("BASE", 24_643_414);

        _setUpTestEnvironment();
        _setupContractLabels();

        superPositionsReceiver = ISuperPositionsReceiver(
            address(
                new SuperPositionsReceiverWrapper(
                    baseChainId, address(gateway), address(SUPERFORM_SUPERPOSITIONS_BASE), users.alice
                )
            )
        );

        // Grant roles
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.ADMIN_ROLE());
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.RECOVERY_ROLE());
        vm.stopPrank();
    }

    function test_SetGateway() public {
        address newGateway = makeAddr("newGateway");

        // Should fail if not admin
        vm.expectRevert();
        superPositionsReceiver.setGateway(newGateway);

        // Should succeed if admin
        vm.prank(users.alice);
        superPositionsReceiver.setGateway(newGateway);
        assertEq(superPositionsReceiver.gateway(), newGateway);
    }

    function test_RecoverFunds() public {
        uint256 amount = 1000;

        deal(USDCE_BASE, address(superPositionsReceiver), 100 * _1_USDCE);

        // Should fail if not recovery admin
        vm.prank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount, users.bob);

        // Should fail on source chain
        vm.chainId(baseChainId);
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("SourceChainRecoveryNotAllowed()"));
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount, users.bob);

        uint256 before = USDCE_BASE.balanceOf(users.alice);
        // Should succeed on destination chain with recovery admin
        vm.chainId(destiChainId);
        vm.prank(users.alice);
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount, users.bob);
        assertEq(USDCE_BASE.balanceOf(users.bob) - before, amount);
    }

    function test_SupportsInterface() public {
        assertTrue(superPositionsReceiver.supportsInterface(0x4e2312e0));
        assertFalse(superPositionsReceiver.supportsInterface(0x12345678));
    }

    // Test setMaxBridgeGasLimit function
    function test_SetMaxBridgeGasLimit() public {
        uint256 newGasLimit = 3_000_000;

        // Should fail when called by non-admin
        vm.startPrank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.setMaxBridgeGasLimit(newGasLimit);
        vm.stopPrank();

        // Should succeed when called by admin
        vm.startPrank(users.alice);
        superPositionsReceiver.setMaxBridgeGasLimit(newGasLimit);
        vm.stopPrank();

        assertEq(superPositionsReceiver.maxBridgeGasLimit(), newGasLimit);
    }

    function testBridgeToken_SuccessfulBridge() public {
        vm.startPrank(users.alice);
        MockERC20 mockToken = new MockERC20("Mock Token", "MTKN", 18);

        // Deploy mock bridge target
        MockBridgeTarget bridgeTarget = new MockBridgeTarget();
        address payable to = payable(address(bridgeTarget));

        uint256 amount = 100 ether;

        address externalReceiver = makeAddr("externalReceiver");

        // Prepare bridge parameters
        bytes memory txData = abi.encodeWithSignature(
            "mockBridgeFunction(address,address,uint256)", address(mockToken), externalReceiver, amount
        );

        // Mint tokens to the SuperPositionsReceiver
        uint256 initialBalance = 1000 ether;
        mockToken.mint(address(superPositionsReceiver), initialBalance);

        vm.expectEmit(true, true, true, true);
        emit SuperPositionsReceiver.TargetWhitelisted(to, true);
        superPositionsReceiver.setTargetWhitelisted(to, true);

        // Expect bridge initiated event
        vm.expectEmit(true, true, true, true);
        emit SuperPositionsReceiver.BridgeInitiated(address(mockToken), amount);

        // Call bridge token
        superPositionsReceiver.bridgeToken(to, txData, address(mockToken), to, amount, 500_000);

        // Check that tokens were transferred out of the contract
        assertEq(
            mockToken.balanceOf(address(superPositionsReceiver)),
            initialBalance - amount,
            "Incorrect token balance after bridge"
        );

        // Additional checks
        assertTrue(bridgeTarget.wasCalled(), "Bridge target was not called");
    }

    function testBridgeToken_FailedBridgeTransaction() public {
        vm.startPrank(users.alice);
        // Deploy mock failure bridge target
        MockFailureBridgeTarget failureBridgeTarget = new MockFailureBridgeTarget();
        address payable to = payable(address(failureBridgeTarget));
        superPositionsReceiver.setTargetWhitelisted(to, true);

        bytes memory txData = abi.encodeWithSignature("mockFailBridgeFunction()");
        uint256 amount = 100 ether;

        // Expect revert
        vm.expectRevert(abi.encodeWithSignature("BridgeTransactionFailed()"));

        // Call bridge token
        superPositionsReceiver.bridgeToken(to, txData, DAI_BASE, to, amount, 500_000);
    }

    function testBridgeToken_ExceedingGasLimit() public {
        vm.startPrank(users.alice);
        // Deploy mock failure bridge target
        MockFailureBridgeTarget failureBridgeTarget = new MockFailureBridgeTarget();
        address payable to = payable(address(failureBridgeTarget));
        superPositionsReceiver.setTargetWhitelisted(to, true);

        bytes memory txData = abi.encodeWithSignature("mockFailBridgeFunction()");
        uint256 amount = 100 ether;

        // Expect revert
        vm.expectRevert(abi.encodeWithSignature("GasLimitExceeded()"));

        // Call bridge token
        superPositionsReceiver.bridgeToken(to, txData, DAI_BASE, to, amount, 5_000_000);
    }

    function testBridgeToken_NoTokensTransferred() public {
        vm.startPrank(users.alice);
        MockERC20 mockToken = new MockERC20("Mock Token", "MTKN", 18);

        // Deploy mock bridge target
        MockBridgeTargetNoTransfer bridgeTarget = new MockBridgeTargetNoTransfer();
        address payable to = payable(address(bridgeTarget));
        superPositionsReceiver.setTargetWhitelisted(to, true);

        uint256 amount = 100 ether;

        address externalReceiver = makeAddr("externalReceiver");

        // Prepare bridge parameters
        bytes memory txData = abi.encodeWithSignature(
            "mockBridgeFunction(address,address,uint256)", address(mockToken), externalReceiver, amount
        );

        // Mint tokens to the SuperPositionsReceiver
        uint256 initialBalance = 1000 ether;
        mockToken.mint(address(superPositionsReceiver), initialBalance);

        // Expect revert
        vm.expectRevert(abi.encodeWithSignature("NoTokensTransferred()"));

        // Call bridge token
        superPositionsReceiver.bridgeToken(to, txData, address(mockToken), to, amount, 500_000);
    }

    // Test for single ERC1155 token received on the source chain
    function test_onERC1155Received_SourceChain() public {
        uint256 superformId = 123; // Example SuperPosition ID
        uint256 amount = 1000 * 10 ** 6; // 1000 USDC

        // Prepare mock SuperPositions contract
        vm.mockCall(
            SUPERFORM_SUPERPOSITIONS_BASE, abi.encodeWithSelector(IERC1155A.safeTransferFrom.selector), abi.encode(true)
        );

        // Prepare test scenario on source chain
        vm.chainId(baseChainId);

        // Give SuperPositions contract permission to send tokens
        vm.prank(address(SUPERFORM_SUPERPOSITIONS_BASE));

        // Call onERC1155Received
        bytes4 response = SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155Received(
            address(this), // operator
            address(0), // from (must be address(0) on source chain)
            superformId, // superformId
            amount, // value
            "" // data
        );

        // Assert the response matches the expected selector
        assertEq(
            response,
            SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155Received.selector,
            "Incorrect response selector"
        );
    }

    // Test for single ERC1155 token received on a destination chain
    function test_onERC1155Received_DestinationChain() public {
        uint256 superformId = 123; // Example SuperPosition ID
        uint256 amount = 1000 * 10 ** 6; // 1000 USDC

        // Switch to destination chain
        vm.chainId(destiChainId);

        // Call onERC1155Received
        SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155Received(
            address(this), // operator
            address(1), // from (non-zero address)
            superformId, // superformId
            amount, // value
            "" // data
        );

        // Since the function returns nothing when not on source chain,
        // we can't assert much beyond ensuring no revert occurs
        assertTrue(true, "Function should not revert on destination chain");
    }

    // Test for batch ERC1155 tokens received on the source chain
    function test_onERC1155BatchReceived_SourceChain() public {
        // Setup: Prepare multiple SuperPosition tokens
        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = 123;
        superformIds[1] = 456;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** 6; // 1000 USDC
        amounts[1] = 500 * 10 ** 6; // 500 USDC

        // Prepare mock SuperPositions contract
        vm.mockCall(
            SUPERFORM_SUPERPOSITIONS_BASE, abi.encodeWithSelector(IERC1155A.safeTransferFrom.selector), abi.encode(true)
        );

        // Prepare test scenario on source chain
        vm.chainId(baseChainId);

        // Give SuperPositions contract permission to send tokens
        vm.prank(address(SUPERFORM_SUPERPOSITIONS_BASE));

        // Call onERC1155BatchReceived
        bytes4 response = SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155BatchReceived(
            address(this), // operator
            address(0), // from (must be address(0) on source chain)
            superformIds, // superformIds
            amounts, // values
            "" // data
        );

        // Assert the response matches the expected selector
        assertEq(
            response,
            SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155BatchReceived.selector,
            "Incorrect response selector"
        );
    }

    // Test for batch ERC1155 tokens received on a destination chain
    function test_onERC1155BatchReceived_DestinationChain() public {
        // Setup: Prepare multiple SuperPosition tokens
        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = 123;
        superformIds[1] = 456;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** 6; // 1000 USDC
        amounts[1] = 500 * 10 ** 6; // 500 USDC

        // Switch to destination chain
        vm.chainId(destiChainId);

        // Call onERC1155BatchReceived
        SuperPositionsReceiver(address(superPositionsReceiver)).onERC1155BatchReceived(
            address(this), // operator
            address(1), // from (non-zero address)
            superformIds, // superformIds
            amounts, // values
            "" // data
        );

        // Since the function returns nothing when not on source chain,
        // we can't assert much beyond ensuring no revert occurs
        assertTrue(true, "Function should not revert on destination chain");
    }
}
