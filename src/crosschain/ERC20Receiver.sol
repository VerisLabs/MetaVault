// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title ERC20Receiver Contract
/// @notice A contract that receives and manages assets and SuperPositions during cross-chain operations
/// @dev Implements ERC1155Receiver to handle SuperPositions and manages ERC20 tokens from failed cross-chain operations
contract ERC20Receiver {
    using SafeTransferLib for address;

    /// @dev The deployer (SuperformGateway) address
    address immutable _deployer;

    /// @dev The ERC20 token address this receiver manages
    address public immutable _asset;

    /// @dev The SuperPositions contract address
    address immutable _superPositions;

    /// @dev Unique identifier for this receiver instance
    bytes32 public key;

    /// @dev Minimum balance expected to be received during operations
    uint256 public minExpectedBalance;

    /// @notice Contract constructor
    /// @param _asset_ The ERC20 token address this receiver will handle
    /// @param _superPositions_ The SuperPositions contract address
    constructor(address _asset_, address _superPositions_) {
        _asset = _asset_;
        _superPositions = _superPositions_;
        _deployer = msg.sender;
    }

    /// @notice Returns the current token balance of the contract
    /// @return The amount of ERC20 tokens held by this contract
    function balance() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /// @notice Transfers tokens back to the deployer (SuperformGateway)
    /// @dev Can only be called by the deployer
    /// @param amount The amount of tokens to transfer
    function pull(uint256 amount) external {
        if (msg.sender != _deployer) revert();
        _asset.safeTransfer(_deployer, amount);
    }

    /// @notice Sets the minimum expected balance for the receiver
    /// @dev Can only be called by the deployer
    /// @param amount The minimum amount of tokens expected
    function setMinExpectedBalance(uint256 amount) external {
        if (msg.sender != _deployer) revert();
        minExpectedBalance = amount;
    }

    /// @notice Initializes the receiver with a unique key
    /// @dev Can only be called by the deployer
    /// @param _key The unique identifier for this receiver instance
    function initialize(bytes32 _key) external {
        if (msg.sender != _deployer) revert();
        key = _key;
        ISuperPositions(_superPositions).setApprovalForAll(_deployer, true);
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
        if (msg.sender != address(_superPositions)) revert();
        if (from != address(0)) revert();
        ISuperformGateway(_deployer).notifyRefund(superformId, value);
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
        from;
        values;
        data;
        if (msg.sender != address(_superPositions)) revert();
        if (from != address(0)) revert();
        ISuperformGateway(_deployer).notifyBatchRefund(superformIds, values);
        return this.onERC1155BatchReceived.selector;
    }
}
