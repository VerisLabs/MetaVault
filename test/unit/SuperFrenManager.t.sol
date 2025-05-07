// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MetaVaultEvents } from "../helpers/MetaVaultEvents.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { console2 } from "forge-std/Test.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import { IMetaVault, ISuperformGateway } from "interfaces/Lib.sol";
import {
    AssetsManager,
    ERC7540Engine,
    EmergencyAssetsManager,
    MetaVaultAdmin,
    SuperFrenRewardsManager
} from "modules/Lib.sol";

import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { MockExternalContract, MockSuperFrens } from "../helpers/mock/MockSuperFrens.sol";

contract SuperFrenManagerTest is BaseVaultTest, MetaVaultEvents {
    using SafeTransferLib for address;

    ISuperformGateway public gateway;
    SuperFrenRewardsManager superFrenManager;

    MetaVaultAdmin admin;

    // // Test addresses
    // address owner = address(0x1);
    // address manager = address(0x2);
    // address user = address(0x3);

    // Contracts
    // SuperFrenRewardsManager superFrenManager;
    MockSuperFrens mockSuperFrens;
    MockERC20 mockERC20;
    MockExternalContract mockExternalContract;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        config.signerRelayer = relayer;
        vault = IMetaVault(address(new MetaVaultWrapper(config)));
        admin = new MetaVaultAdmin();
        vault.addFunctions(admin.selectors(), address(admin), false);
        gateway = deployGatewayBase(address(vault), users.alice);
        vault.setGateway(address(gateway));
        gateway.grantRoles(users.alice, gateway.RELAYER_ROLE());

        superFrenManager = new SuperFrenRewardsManager();
        bytes4[] memory managerSelectors = superFrenManager.selectors();
        vault.addFunctions(managerSelectors, address(superFrenManager), false);

        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ADMIN_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        mockSuperFrens = new MockSuperFrens();
        mockERC20 = new MockERC20("test", "TEST", 18);
        mockExternalContract = new MockExternalContract();

        console2.log("vault address : %s", address(vault));
        console2.log("recovery address : %s", gateway.recoveryAddress());
    }

    function _setupContractLabels() public {
        vm.label(address(vault), "MetaVault");
        vm.label(address(superFrenManager), "SuperFrenManager");
        vm.label(address(mockSuperFrens), "MockSuperFrens");
        vm.label(address(mockERC20), "MockERC20");
        vm.label(address(mockExternalContract), "MockExternalContract");
    }

    function setUp() public {
        super._setUp("BASE", 26_668_569);

        _setUpTestEnvironment();
        _setupContractLabels();
        vm.stopPrank();
    }

    function test_AddNFTContract() public {
        vm.prank(users.alice);

        console2.log(
            "### ~ SuperFrenManager.t.sol:80 ~ test_AddNFTContract ~ address(mockSuperFrens):", address(mockSuperFrens)
        );
        superFrenManager.addNFTContract(address(mockSuperFrens));

        assertTrue(superFrenManager.approvedNFTContracts(address(mockSuperFrens)), "NFT contract should be approved");
    }

    function test_AddNFTContract_NotManager() public {
        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.addNFTContract(address(mockSuperFrens));
    }

    function test_AddNFTContract_ZeroAddress() public {
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        superFrenManager.addNFTContract(address(0));
    }

    function test_RemoveNFTContract() public {
        // First add the contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        // Then remove it
        vm.prank(users.alice);
        superFrenManager.removeNFTContract(address(mockSuperFrens));

        assertFalse(superFrenManager.approvedNFTContracts(address(mockSuperFrens)), "NFT contract should beremoved");
    }

    function test_RemoveNFTContract_NotManager() public {
        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.removeNFTContract(address(mockSuperFrens));
    }

    function test_RegisterFunction() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        vm.prank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit FunctionRegisteredSuperFren(address(mockExternalContract), functionSelector, "testFunction");

        superFrenManager.registerFunction(address(mockExternalContract), functionSelector, "testFunction");

        assertTrue(
            superFrenManager.registeredFunctions(address(mockExternalContract), functionSelector),
            "Function should be registered"
        );
    }

    function test_RegisterFunction_NotManager() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.registerFunction(address(mockExternalContract), functionSelector, "testFunction");
    }

    function test_RegisterFunction_ZeroAddress() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        superFrenManager.registerFunction(address(0), functionSelector, "testFunction");
    }

    function test_RemoveFunction() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        // First register the function
        vm.prank(users.alice);
        superFrenManager.registerFunction(address(mockExternalContract), functionSelector, "testFunction");

        // Then remove it
        vm.prank(users.alice);
        vm.expectEmit(true, true, false, false);
        emit FunctionRemovedSuperFren(address(mockExternalContract), functionSelector);

        superFrenManager.removeFunction(address(mockExternalContract), functionSelector);

        assertFalse(
            superFrenManager.registeredFunctions(address(mockExternalContract), functionSelector),
            "Function should be removed"
        );
    }

    function test_RemoveFunction_NotManager() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.removeFunction(address(mockExternalContract), functionSelector);
    }

    function test_ExecuteFunction() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        // Register the function
        vm.prank(users.alice);
        superFrenManager.registerFunction(address(mockExternalContract), functionSelector, "testFunction");

        // Prepare call data
        bytes memory callData = abi.encodeWithSelector(functionSelector, uint256(123));

        // Execute the function
        vm.prank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit DynamicFunctionCalledSuperFren(address(mockExternalContract), functionSelector, true);

        (bool success, bytes memory returnData) =
            superFrenManager.executeFunction(address(mockExternalContract), callData, 0);

        assertTrue(success, "Function call should succeed");
        assertTrue(mockExternalContract.functionCalled(), "Function should be called on target contract");
    }

    function test_ExecuteFunction_NotRegistered() public {
        bytes4 functionSelector = MockExternalContract.testFunction.selector;

        // Don't register the function

        // Prepare call data
        bytes memory callData = abi.encodeWithSelector(functionSelector, uint256(123));

        // Execute the function
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("FunctionNotRegisteredSuperFren()"));

        superFrenManager.executeFunction(address(mockExternalContract), callData, 0);
    }

    function test_ExecuteFunction_CallFails() public {
        bytes4 functionSelector = MockExternalContract.failingFunction.selector;

        // Register the function
        vm.prank(users.alice);
        superFrenManager.registerFunction(address(mockExternalContract), functionSelector, "failingFunction");

        // Prepare call data
        bytes memory callData = abi.encodeWithSelector(functionSelector);

        // Execute the function
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("FunctionCallFailedSuperFren()"));

        superFrenManager.executeFunction(address(mockExternalContract), callData, 0);
    }

    function test_ClaimNFT() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 editionId = 1;
        uint256 tierId = 5;
        bytes32[] memory proof = new bytes32[](0);

        // Call claim NFT
        vm.prank(users.alice);
        vm.expectEmit(true, true, true, false);
        emit NFTClaimedSuperFren(address(mockSuperFrens), editionId, tierId);

        superFrenManager.claimNFT(address(mockSuperFrens), editionId, tierId, proof);

        // Check that the NFT was received
        assertEq(mockSuperFrens.balanceOf(address(superFrenManager), tierId), 1, "Manager should have received the NFT");
    }

    function test_ClaimNFT_NotManager() public {
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 editionId = 1;
        uint256 tierId = 5;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.claimNFT(address(mockSuperFrens), editionId, tierId, proof);
    }

    function test_ClaimNFT_NotApprovedContract() public {
        // Don't approve the NFT contract

        uint256 editionId = 1;
        uint256 tierId = 5;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidNFTContractSuperFren()"));
        superFrenManager.claimNFT(address(mockSuperFrens), editionId, tierId, proof);
    }

    function test_BatchClaimNFTs() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256[] memory editionIds = new uint256[](2);
        editionIds[0] = 1;
        editionIds[1] = 2;

        uint256[] memory tierIds = new uint256[](2);
        tierIds[0] = 5;
        tierIds[1] = 6;

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        // Call batch claim NFTs
        vm.prank(users.alice);
        superFrenManager.batchClaimNFTs(address(mockSuperFrens), editionIds, tierIds, proofs);

        // Check that the NFTs were received
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[0]),
            1,
            "Manager should have received the first NFT"
        );
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[1]),
            1,
            "Manager should have received the second NFT"
        );
    }

    function test_ForgeNFT() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 tierId = 5;

        // Mint 5 tokens of the tier ID to forge
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));

        // Call forge NFT
        vm.prank(users.alice);
        vm.expectEmit(true, true, true, false);
        emit NFTForgedSuperFren(address(mockSuperFrens), tierId, tierId - 1);

        superFrenManager.forgeNFT(address(mockSuperFrens), tierId);

        // Check that the NFTs were forged
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierId),
            0,
            "Manager should have 0 of the original tier after forging"
        );
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierId - 1),
            1,
            "Manager should have 1 of the forged tier"
        );
    }

    function test_ForgeNFT_NotEnoughTokens() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 tierId = 5;

        // Mint only 4 tokens (need 5 to forge)
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));

        // Call forge NFT
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("NotEnoughTokensToForgeSuperFren()"));
        superFrenManager.forgeNFT(address(mockSuperFrens), tierId);
    }

    function test_BatchForgeNFTs() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256[] memory tierIds = new uint256[](2);
        tierIds[0] = 5;
        tierIds[1] = 6;

        // Mint 5 tokens of each tier ID to forge
        for (uint256 i = 0; i < 5; i++) {
            mockSuperFrens.claim(address(superFrenManager), 0, tierIds[0], new bytes32[](0));
            mockSuperFrens.claim(address(superFrenManager), 0, tierIds[1], new bytes32[](0));
        }

        // Call batch forge NFTs
        vm.prank(users.alice);
        superFrenManager.batchForgeNFTs(address(mockSuperFrens), tierIds);

        // Check that the NFTs were forged
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[0]),
            0,
            "Manager should have 0 of the first tier after forging"
        );
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[1]),
            0,
            "Manager should have 0 of the second tier after forging"
        );
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[0] - 1),
            1,
            "Manager should have 1 of the first forged tier"
        );
        assertEq(
            mockSuperFrens.balanceOf(address(superFrenManager), tierIds[1] - 1),
            1,
            "Manager should have 1 of the second forged tier"
        );
    }

    function test_GetNFTBalance() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 tierId = 5;

        // Mint 3 tokens of the tier ID
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, tierId, new bytes32[](0));

        // Check the balance
        uint256 balance = superFrenManager.getNFTBalance(address(mockSuperFrens), tierId);
        assertEq(balance, 3, "NFT balance should be 3");
    }

    function test_HasCompleteNFTSet_True() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 startTierId = 10;
        uint256 count = 8;

        // Mint 1 token of each tier ID in the set
        for (uint256 i = 0; i < count; i++) {
            mockSuperFrens.claim(address(superFrenManager), 0, startTierId + i, new bytes32[](0));
        }

        // Check if the set is complete
        bool isComplete = superFrenManager.hasCompleteNFTSet(address(mockSuperFrens), startTierId, count);
        assertTrue(isComplete, "NFT set should be complete");
    }

    function test_HasCompleteNFTSet_False() public {
        // Approve the NFT contract
        vm.prank(users.alice);
        superFrenManager.addNFTContract(address(mockSuperFrens));

        uint256 startTierId = 10;
        uint256 count = 8;

        // Mint 1 token of each tier ID in the set except for one
        for (uint256 i = 0; i < count; i++) {
            if (i != 3) {
                // Skip one ID
                mockSuperFrens.claim(address(superFrenManager), 0, startTierId + i, new bytes32[](0));
            }
        }

        // Check if the set is complete
        bool isComplete = superFrenManager.hasCompleteNFTSet(address(mockSuperFrens), startTierId, count);
        assertFalse(isComplete, "NFT set should not be complete");
    }

    function test_OnERC1155Received() public {
        uint256 id = 5;
        uint256 value = 1;

        vm.expectEmit(true, true, true, true);
        emit NFTReceivedSuperFren(address(this), address(this), id, value);

        bytes4 response = superFrenManager.onERC1155Received(address(this), address(this), id, value, "");

        assertEq(response, superFrenManager.onERC1155Received.selector, "Should return correct selector");
    }

    function test_OnERC1155BatchReceived() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 5;
        ids[1] = 6;

        uint256[] memory values = new uint256[](2);
        values[0] = 1;
        values[1] = 2;

        vm.expectEmit(true, true, true, true);
        emit NFTBatchReceivedSuperFren(address(this), address(this), ids, values);

        bytes4 response = superFrenManager.onERC1155BatchReceived(address(this), address(this), ids, values, "");

        assertEq(response, superFrenManager.onERC1155BatchReceived.selector, "Should return correct selector");
    }

    function test_SupportsInterface() public {
        // ERC1155 receiver interface ID
        bool supportsERC1155Receiver = superFrenManager.supportsInterface(0x4e2312e0);
        assertTrue(supportsERC1155Receiver, "Should support ERC1155 receiver interface");

        // Random interface ID
        bool supportsRandomInterface = superFrenManager.supportsInterface(0x12345678);
        assertFalse(supportsRandomInterface, "Should not support random interface");
    }

    function test_EmergencyWithdrawERC20() public {
        // Mint some tokens to the manager
        mockERC20.mint(address(superFrenManager), 1000);

        uint256 amount = 500;

        // Call emergency withdraw
        vm.prank(users.alice);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalSuperFren(address(mockERC20), (users.alice), amount);

        superFrenManager.emergencyWithdrawERC20(address(mockERC20), (users.alice), amount);

        // Check that the tokens were transferred
        assertEq(mockERC20.balanceOf(users.bob), amount, "User should have received the withdrawn tokens");
    }

    function test_EmergencyWithdrawERC20_NotOwner() public {
        mockERC20.mint(address(superFrenManager), 1000);

        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.emergencyWithdrawERC20(address(mockERC20), (users.bob), 500);
    }

    function test_EmergencyWithdrawERC20_ZeroAddress() public {
        mockERC20.mint(address(superFrenManager), 1000);

        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        superFrenManager.emergencyWithdrawERC20(address(mockERC20), address(0), 500);
    }

    function test_EmergencyWithdrawERC1155() public {
        uint256 id = 5;
        uint256 amount = 3;

        // Mint some NFTs to the manager
        mockSuperFrens.claim(address(superFrenManager), 0, id, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, id, new bytes32[](0));
        mockSuperFrens.claim(address(superFrenManager), 0, id, new bytes32[](0));

        // Call emergency withdraw
        vm.prank(users.alice);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalSuperFren(address(mockSuperFrens), (users.bob), amount);

        superFrenManager.emergencyWithdrawERC1155(address(mockSuperFrens), (users.bob), id, amount);

        // Check that the NFTs were transferred
        assertEq(mockSuperFrens.balanceOf((users.bob), id), amount, "User should have received the withdrawn NFTs");
    }

    function test_EmergencyWithdrawERC1155_NotOwner() public {
        uint256 id = 5;

        mockSuperFrens.claim(address(superFrenManager), 0, id, new bytes32[](0));

        vm.prank(users.bob);
        vm.expectRevert();
        superFrenManager.emergencyWithdrawERC1155(address(mockSuperFrens), (users.bob), id, 1);
    }

    function test_EmergencyWithdrawERC1155_ZeroAddress() public {
        uint256 id = 5;

        mockSuperFrens.claim(address(superFrenManager), 0, id, new bytes32[](0));

        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        superFrenManager.emergencyWithdrawERC1155(address(mockSuperFrens), address(0), id, 1);
    }
}
