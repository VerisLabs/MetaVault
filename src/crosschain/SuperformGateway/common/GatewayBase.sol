// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20Receiver } from "crosschain/Lib.sol";
import { IBaseRouter, IMetaVault, ISuperPositions, ISuperRegistry } from "interfaces/Lib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";

import { LibClone } from "solady/utils/LibClone.sol";

/// @title GatewayBase Contract for SuperformGateway Modules
/// @author Unlockd
/// @notice Base storage contract containing all shared state variables and helper functions for SuperformGateway
/// modules
/// @dev Implements role-based access control and core vault functionality
contract GatewayBase is OwnableRoles {
    /// @notice Emitted when a new receiver contract is deployed
    event ReceiverDeployed(bytes32 indexed key, address indexed receiver);

    /// @notice Thrown when an unauthorized address attempts to call a function
    error NotVault();

    /// @notice Modifier that restricts function access to the vault contract
    modifier onlyVault() {
        if (msg.sender != address(vault)) {
            revert NotVault();
        }
        _;
    }

    /// @notice Modifier to refund dust ether for crosschain transactions
    /// @dev Reverts if the msg.value was not enough
    modifier refundGas() {
        uint256 balanceBefore;
        assembly {
            balanceBefore := sub(selfbalance(), callvalue())
        }
        _;
        assembly {
            let balanceAfter := selfbalance()
            switch lt(balanceAfter, balanceBefore)
            case true {
                mstore(0x00, 0x1c26714c) // `InsufficientGas()`.
                revert(0x1c, 0x04)
            }
            case false {
                // Transfer all the ETH to sender and check if it succeeded or not.
                if iszero(call(gas(), origin(), balanceAfter, codesize(), 0x00, codesize(), 0x00)) {
                    mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice Data structure for cross-chain requests
    /// @param controller Address controlling the request
    /// @param superformIds Array of Superform IDs involved in request
    /// @param requestedAssetsPerVault Array of requested assets per vault
    /// @param requestedAssets Total requested assets
    /// @param receiverAddress Address to receive assets
    /// @param hasReceiver Flag to check if receiver is deployed
    struct RequestData {
        address controller;
        uint256[] superformIds;
        uint256[] requestedAssetsPerVault;
        uint256 requestedAssets;
        address receiverAddress;
        bool hasReceiver;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for relayer
    uint256 public constant RELAYER_ROLE = _ROLE_1;

    /// @notice ERC20Receiver contract implementation to clone
    address public receiverImplementation;

    /// @notice Superpositions contract interface
    ISuperPositions public superPositions;

    /// @notice Superform router interface
    IBaseRouter public superformRouter;

    /// @notice Superform regitry interface
    ISuperRegistry public superRegistry;

    /// @notice Underlying vault interface
    IMetaVault public vault;

    /// @notice Asset address
    address public asset;

    /// @notice Recovery address for failed transactions
    address public recoveryAddress;

    /// @notice Mapping of request keys to receiver addresses
    mapping(bytes32 => address) public receivers;

    /// @notice Total pending cross-chain investments
    uint256 public totalpendingXChainInvests;

    /// @notice Mapping of superform IDs to pending investment amounts
    mapping(uint256 => uint256) public pendingXChainInvests;

    /// @notice Total pending cross-chain divests
    uint256 public totalPendingXChainDivests;

    /// @notice Queue of all active requests
    EnumerableSetLib.Bytes32Set internal _requestsQueue;

    /// @notice Mapping of controller addresses to nonces
    mapping(address => uint256) nonces;

    /// @notice Mapping of request keys to request data
    mapping(bytes32 => RequestData) public requests;

    /// @notice Thrown when an invalid request key is provided
    error InvalidKey();

    /// @dev Returns the delegatee of a owner to receive the assets
    /// @dev If it doesnt exist it deploys it at the moment
    /// @notice receiverAddress returns delegatee
    function getReceiver(bytes32 key) public returns (address receiverAddress) {
        if (key == bytes32(0)) revert InvalidKey();
        address current = receivers[key];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress = LibClone.clone(receiverImplementation);
            ERC20Receiver(receiverAddress).initialize(key);
            receivers[key] = receiverAddress;
            emit ReceiverDeployed(key, receiverAddress);
        }
    }
}
