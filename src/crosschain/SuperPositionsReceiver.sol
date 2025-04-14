// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title SuperPositionsReceiver
/// @notice A cross-chain recovery contract for failed SuperPosition investments
/// @dev This contract must be deployed with identical addresses across all chains to handle failed cross-chain
/// operations.
contract SuperPositionsReceiver is OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @notice Emitted when a bridge operation is initiated
    event BridgeInitiated(address indexed token, uint256 amount);

    /// @notice Emitted when a target contract is whitelisted
    event TargetWhitelisted(address indexed target, bool status);

    /// @notice Error thrown when the gas limit for a bridge transaction is exceeded
    error GasLimitExceeded();

    /// @notice Error thrown when no tokens are transferred in a bridge operation
    error NoTokensTransferred();

    /// @notice Error thrown when a target address is not whitelisted
    error TargetNotWhitelisted();

    /// @notice Error thrown when a bridge transaction fails
    error BridgeTransactionFailed();

    /// @notice Error thrown when recovery from the source chain is not allowed
    error SourceChainRecoveryNotAllowed();

    /// @notice Role identifier for admin privileges
    /// @dev Admins can manage contract configuration and roles
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for recovery admin privileges
    /// @dev Recovery admins can execute fund recovery operations
    uint256 public constant RECOVERY_ROLE = _ROLE_1;

    /// @notice The chain ID of the source chain where the gateway is deployed
    /// @dev Used to differentiate between source and destination chain behaviors
    uint64 public sourceChain;

    /// @notice The address of the SuperformGateway contract
    /// @dev Gateway contract that handles cross-chain SuperPosition operations
    address public gateway;

    /// @notice The address of the SuperPositions (ERC1155) contract
    /// @dev Contract that manages the SuperPosition tokens
    address public superPositions;

    /// @notice Maximum gas limit for bridge calls
    /// @dev Prevents excessive gas consumption in bridge transactions
    uint256 public maxBridgeGasLimit;

    /// @notice Mapping to track whitelisted bridge target addresses
    /// @dev Only whitelisted targets can be used in bridgeToken function
    mapping(address => bool) public whitelistedTargets;

    /// @notice Initializes the receiver with source chain and contract addresses
    /// @dev Sets up the contract with necessary addresses and grants initial admin roles
    /// @param _sourceChain The chain ID where the original gateway is deployed
    /// @param _gateway Address of the SuperformGateway contract
    /// @param _superPositions Address of the SuperPositions contract
    constructor(uint64 _sourceChain, address _gateway, address _superPositions, address _owner) {
        sourceChain = _sourceChain;
        gateway = _gateway;
        superPositions = _superPositions;
        maxBridgeGasLimit = 2_000_000; // Default gas limit
        // Initialize ownership and grant admin role
        _initializeOwner(_owner);
        _grantRoles(_owner, ADMIN_ROLE);
    }

    function setGateway(address _gateway) external onlyRoles(ADMIN_ROLE) {
        gateway = _gateway;
    }

    /// @notice Updates the maximum gas limit for bridge calls
    /// @dev Only callable by admin
    /// @param _maxGasLimit New maximum gas limit
    function setMaxBridgeGasLimit(uint256 _maxGasLimit) external onlyRoles(ADMIN_ROLE) {
        maxBridgeGasLimit = _maxGasLimit;
    }

    /// @notice Adds or removes a target contract from the whitelist
    /// @dev Only callable by admin
    /// @param _target The address of the target contract
    /// @param _status True to whitelist, false to remove from whitelist
    function setTargetWhitelisted(address _target, bool _status) external onlyRoles(ADMIN_ROLE) {
        whitelistedTargets[_target] = _status;
        emit TargetWhitelisted(_target, _status);
    }

    /// @notice Recovers stuck tokens from failed cross-chain operations
    /// @dev Can only be called by addresses with RECOVERY_ROLE and only on destination chains
    /// @param token The address of the token to recover
    /// @param amount The amount of tokens to recover
    function recoverFunds(address token, uint256 amount, address to) external onlyRoles(RECOVERY_ROLE) {
        if (sourceChain == block.chainid) revert SourceChainRecoveryNotAllowed();
        token.safeTransfer(to, amount);
    }

    /// @notice Bridges tokens to a specified address by executing a low-level call
    /// @dev Ensures token approval before execution and reverts if the transaction fails
    /// @param _bridgeTarget The address receiving the bridged tokens
    /// @param _callData Encoded transaction data for the bridge operation
    /// @param _token The address of the token to bridge
    /// @param _allowanceTarget The address to approve the token transfer
    /// @param _amount The amount of tokens to bridge
    /// @param _gasLimit The gas limit for the bridging and swapping
    function bridgeToken(
        address payable _bridgeTarget,
        bytes memory _callData,
        address _token,
        address _allowanceTarget,
        uint256 _amount,
        uint256 _gasLimit
    )
        external
        nonReentrant
        onlyRoles(RECOVERY_ROLE)
    {
        // Check if the bridge target is whitelisted
        if (!whitelistedTargets[_bridgeTarget]) revert TargetNotWhitelisted();

        if (_gasLimit > maxBridgeGasLimit) revert GasLimitExceeded();
        // Pre-transaction balance check
        uint256 initialBalance = _token.balanceOf(address(this));

        _token.safeApproveWithRetry(_allowanceTarget, _amount);

        // Attempt bridge transaction with additional error capturing
        (bool success,) = _bridgeTarget.call{ gas: _gasLimit }(_callData);

        if (!success) {
            revert BridgeTransactionFailed();
        }

        // Verify token movement
        uint256 finalBalance = _token.balanceOf(address(this));
        if (finalBalance >= initialBalance) revert NoTokensTransferred();
        _token.safeApproveWithRetry(_allowanceTarget, 0);
        emit BridgeInitiated(_token, _amount);
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
        data;
        if (sourceChain == block.chainid) {
            if (msg.sender != address(superPositions)) revert();
            if (from != address(0)) revert();
            ISuperPositions(superPositions).safeTransferFrom(address(this), address(gateway), superformId, value, "");
            return this.onERC1155Received.selector;
        }
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
