// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { GatewayBase, IBaseRouter, IMetaVault, ISuperPositions, ISuperRegistry } from "./common/GatewayBase.sol";
import { MultiFacetProxy } from "common/Lib.sol";
import { ERC20Receiver } from "crosschain/Lib.sol";

import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { VaultData, VaultLib } from "types/Lib.sol";

/// @title SuperformGateway gateway contract for all crosschain operations involving Superform protofol
/// @author Unlockd
/// @notice Uses a modular proxy pattern similar to diamond pattern to easily upgrade functionality
/// @dev Inherits from GatewayBase
contract SuperformGateway is GatewayBase, MultiFacetProxy {
    using VaultLib for VaultData;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;

    /// @notice Initializes the gateway contract
    /// @param _vault Address of the MetaVault contract
    /// @param _superformRouter Address of Superform's router contract
    /// @param _superPositions Address of Superform's ERC1155 contract
    constructor(
        IMetaVault _vault,
        IBaseRouter _superformRouter,
        ISuperPositions _superPositions,
        ISuperRegistry _superRegistry,
        address owner
    )
        MultiFacetProxy(ADMIN_ROLE)
    {
        vault = _vault;
        asset = vault.asset();
        superformRouter = _superformRouter;
        superPositions = _superPositions;
        superRegistry = _superRegistry;

        // Deploy and set the receiver implementation
        receiverImplementation = address(new ERC20Receiver(asset, address(superPositions)));

        // Set up approvals
        asset.safeApprove(address(superformRouter), type(uint256).max);
        asset.safeApprove(address(vault), type(uint256).max);
        superPositions.setApprovalForAll(address(superformRouter), true);

        // Initialize ownership and grant admin role
        _initializeOwner(owner);
        _grantRoles(owner, ADMIN_ROLE);
    }

    function setVault(IMetaVault _vault) external onlyRoles(ADMIN_ROLE) {
        asset.safeApprove(address(vault), 0);
        vault = _vault;
        asset.safeApprove(address(vault), type(uint256).max);
    }

    function setRouter(IBaseRouter _superformRouter) external onlyRoles(ADMIN_ROLE) {
        asset.safeApprove(address(superformRouter), 0);
        superformRouter = _superformRouter;
        asset.safeApprove(address(superformRouter), type(uint256).max);
    }

    function setSuperPositions(ISuperPositions _superPositions) external onlyRoles(ADMIN_ROLE) {
        superPositions.setApprovalForAll(address(superformRouter), false);
        superPositions = _superPositions;
        superPositions.setApprovalForAll(address(superformRouter), true);
    }

    /// @notice Gets the current queue of pending request IDs
    /// @dev Returns an array of all active request IDs in the queue
    /// @return requestIds Array of pending request IDs
    function getRequestsQueue() public view returns (bytes32[] memory requestIds) {
        return _requestsQueue.values();
    }

    /// @notice Gets the balance of a specific Superform ID for an account
    /// @param account The address to check the balance for
    /// @param superformId The ID of the Superform position
    /// @return The balance of the specified Superform ID
    function balanceOf(address account, uint256 superformId) external view returns (uint256) {
        return superPositions.balanceOf(account, superformId);
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool isSupported) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    /// @dev This function is called at the end of a `safeTransferFrom` after the balance has been updated
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param superformId The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint,uint,bytes)"))`
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        value;
        data;
        if (msg.sender != address(superPositions)) revert Unauthorized();
        if (from == address(vault)) return this.onERC1155Received.selector;
        try ERC20Receiver(from).key() returns (bytes32 key) {
            if (requests[key].receiverAddress == from) {
                return this.onERC1155Received.selector;
            }
        } catch { }
        if (from != recoveryAddress) revert Unauthorized();
        VaultData memory vaultObj = vault.getVault(superformId);
        uint256 investedAssets = pendingXChainInvests[superformId];
        delete pendingXChainInvests[superformId];
        uint256 bridgedAssets = vaultObj.convertToAssets(value, asset, false);
        totalpendingXChainInvests -= investedAssets;
        superPositions.safeTransferFrom(address(this), address(vault), superformId, value, "");
        vault.settleXChainInvest(superformId, bridgedAssets);
        return this.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    /// @dev This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the tokens
    /// @param superformIds An array containing ids of each token being transferred (order and length must match values
    /// array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids
    /// array)
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint[],uint[],bytes)"))`
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        data;
        for (uint256 i = 0; i < superformIds.length; ++i) {
            onERC1155Received(address(0), from, superformIds[i], values[i], "");
        }
        return this.onERC1155BatchReceived.selector;
    }
}
