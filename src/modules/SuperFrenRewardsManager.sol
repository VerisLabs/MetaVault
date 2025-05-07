// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ISuperFrens } from "../interfaces/ISuperFrens.sol";
import { ModuleBase } from "common/Lib.sol";
import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title SuperFrenRewardsManager
/// @notice Manages SuperFren NFTs for maxAPY vaults, enabling NFT minting, purchasing, holding and yield boosting
contract SuperFrenRewardsManager is ModuleBase {
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when a transfer operation fails
    error TransferFailedSuperFren();

    /// @notice Thrown when an invalid NFT contract is provided
    error InvalidNFTContractSuperFren();

    /// @notice Thrown when an invalid zero address is encountered
    error InvalidZeroAddress();

    /// @notice Thrown when there aren't enough tokens to forge higher tier
    error NotEnoughTokensToForgeSuperFren();

    /// @notice Thrown when an external function call fails
    error FunctionCallFailedSuperFren();

    /// @notice Thrown when attempting to call an unregistered function
    error FunctionNotRegisteredSuperFren();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an NFT is claimed
    event NFTClaimedSuperFren(address indexed superFrenContract, uint256 indexed editionId, uint256 indexed tierId);

    /// @notice Emitted when an NFT is received
    event NFTReceivedSuperFren(address indexed operator, address indexed from, uint256 indexed id, uint256 value);

    /// @notice Emitted when multiple NFTs are received
    event NFTBatchReceivedSuperFren(address indexed operator, address indexed from, uint256[] ids, uint256[] values);

    /// @notice Emitted when NFTs are forged into higher tier
    event NFTForgedSuperFren(address indexed superFrenContract, uint256 indexed tierId, uint256 indexed forgedTierId);

    /// @notice Emitted when an emergency withdrawal occurs
    event EmergencyWithdrawalSuperFren(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when a function is registered
    event FunctionRegisteredSuperFren(address indexed targetContract, bytes4 indexed functionSelector, string name);

    /// @notice Emitted when a function registration is removed
    event FunctionRemovedSuperFren(address indexed targetContract, bytes4 indexed functionSelector);

    /// @notice Emitted when a dynamic function is called
    event DynamicFunctionCalledSuperFren(address indexed targetContract, bytes4 indexed functionSelector, bool success);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mapping of SuperFrens NFT contracts that this manager can interact with
    mapping(address => bool) public approvedNFTContracts;

    /// @notice Maps target contract address => function selector => is registered
    mapping(address => mapping(bytes4 => bool)) public registeredFunctions;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Modifier to check if the NFT contract is approved
    modifier onlyApprovedNFTContract(address _nftContract) {
        if (!approvedNFTContracts[_nftContract]) revert InvalidNFTContractSuperFren();
        _;
    }

    /// @notice Modifier to check for invalid parameters (address(0))
    modifier validAddress(address _address) {
        if (_address == address(0)) revert InvalidZeroAddress();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Add an approved SuperFrens NFT contract
    /// @param _nftContract The address of the SuperFrens contract
    function addNFTContract(address _nftContract) external onlyRoles(ADMIN_ROLE) validAddress(_nftContract) {
        approvedNFTContracts[_nftContract] = true;
    }

    /// @notice Remove a SuperFrens NFT contract from approved list
    /// @param _nftContract The address to remove
    function removeNFTContract(address _nftContract) external onlyRoles(ADMIN_ROLE) {
        approvedNFTContracts[_nftContract] = false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    FUNCTION REGISTRY                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Register a new function that can be called on external contracts
    /// @param _targetContract The contract address to interact with
    /// @param _functionSelector The 4-byte function selector
    /// @param _name A human-readable name for the function
    function registerFunction(
        address _targetContract,
        bytes4 _functionSelector,
        string memory _name
    )
        external
        onlyRoles(ADMIN_ROLE)
        validAddress(_targetContract)
    {
        registeredFunctions[_targetContract][_functionSelector] = true;

        emit FunctionRegisteredSuperFren(_targetContract, _functionSelector, _name);
    }

    /// @notice Remove a registered function
    /// @param _targetContract The contract address
    /// @param _functionSelector The function selector to remove
    function removeFunction(address _targetContract, bytes4 _functionSelector) external onlyRoles(ADMIN_ROLE) {
        registeredFunctions[_targetContract][_functionSelector] = false;

        emit FunctionRemovedSuperFren(_targetContract, _functionSelector);
    }

    /// @notice Execute a registered function on an external contract
    /// @param _targetContract The contract to call
    /// @param _data The complete call data (includes function selector)
    /// @param _value ETH value to send with the call
    /// @return success Whether the call succeeded
    /// @return returnData Data returned from the call
    function executeFunction(
        address _targetContract,
        bytes calldata _data,
        uint256 _value
    )
        external
        payable
        onlyRoles(MANAGER_ROLE)
        returns (bool success, bytes memory returnData)
    {
        // Extract function selector from calldata
        bytes4 functionSelector;
        if (_data.length >= 4) {
            assembly {
                functionSelector := calldataload(_data.offset)
            }
        }

        if (!registeredFunctions[_targetContract][functionSelector]) revert FunctionNotRegisteredSuperFren();

        (success, returnData) = _targetContract.call{ value: _value }(_data);

        emit DynamicFunctionCalledSuperFren(_targetContract, functionSelector, success);

        if (!success) revert FunctionCallFailedSuperFren();

        return (success, returnData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  SUPERFRENS INTERACTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Claim a SuperFren NFT from an eligible edition and tier
    /// @param _superFrenContract Address of the SuperFrens contract
    /// @param _editionId The edition ID of the NFT
    /// @param _tierId The tier ID to claim
    /// @param _proof The Merkle proof required for claiming
    function claimNFT(
        address _superFrenContract,
        uint256 _editionId,
        uint256 _tierId,
        bytes32[] calldata _proof
    )
        external
        onlyRoles(MANAGER_ROLE)
        onlyApprovedNFTContract(_superFrenContract)
    {
        ISuperFrens(_superFrenContract).claim(address(this), _editionId, _tierId, _proof);

        emit NFTClaimedSuperFren(_superFrenContract, _editionId, _tierId);
    }

    /// @notice Batch claim SuperFren NFTs from multiple editions and tiers
    /// @param _superFrenContract Address of the SuperFrens contract
    /// @param _editionIds Array of edition IDs
    /// @param _tierIds Array of tier IDs
    /// @param _proofs Array of Merkle proofs for each claim
    function batchClaimNFTs(
        address _superFrenContract,
        uint256[] calldata _editionIds,
        uint256[] calldata _tierIds,
        bytes32[][] calldata _proofs
    )
        external
        onlyRoles(MANAGER_ROLE)
        onlyApprovedNFTContract(_superFrenContract)
    {
        ISuperFrens(_superFrenContract).batchClaim(address(this), _editionIds, _tierIds, _proofs);

        for (uint256 i = 0; i < _editionIds.length; i++) {
            emit NFTClaimedSuperFren(_superFrenContract, _editionIds[i], _tierIds[i]);
        }
    }

    /// @notice Forge SuperFren NFTs to upgrade tiers (burn 5 lower tier to get 1 higher tier)
    /// @param _superFrenContract Address of the SuperFrens contract
    /// @param _tierId The tier ID to forge
    function forgeNFT(
        address _superFrenContract,
        uint256 _tierId
    )
        external
        onlyRoles(MANAGER_ROLE)
        onlyApprovedNFTContract(_superFrenContract)
    {
        if (ERC1155(_superFrenContract).balanceOf(address(this), _tierId) < 5) revert NotEnoughTokensToForgeSuperFren();

        ISuperFrens(_superFrenContract).forge(_tierId);

        emit NFTForgedSuperFren(_superFrenContract, _tierId, _tierId - 1);
    }

    /// @notice Batch forge multiple NFTs
    /// @param _superFrenContract Address of the SuperFrens contract
    /// @param _tierIds Array of tier IDs to forge
    function batchForgeNFTs(
        address _superFrenContract,
        uint256[] calldata _tierIds
    )
        external
        onlyRoles(MANAGER_ROLE)
        onlyApprovedNFTContract(_superFrenContract)
    {
        for (uint256 i = 0; i < _tierIds.length; i++) {
            if (ERC1155(_superFrenContract).balanceOf(address(this), _tierIds[i]) < 5) {
                revert NotEnoughTokensToForgeSuperFren();
            }
        }

        ISuperFrens(_superFrenContract).batchForge(_tierIds);

        for (uint256 i = 0; i < _tierIds.length; i++) {
            emit NFTForgedSuperFren(_superFrenContract, _tierIds[i], _tierIds[i] - 1);
        }
    }

    /// @notice Check NFT balances for a specific tier
    /// @param _superFrenContract The SuperFrens contract address
    /// @param _tierId The tier ID to check
    /// @return The balance of NFTs for the specified tier
    function getNFTBalance(address _superFrenContract, uint256 _tierId) external view returns (uint256) {
        return ERC1155(_superFrenContract).balanceOf(address(this), _tierId);
    }

    /// @notice Check if this contract has a complete set of NFTs for a specific tier
    /// @param _superFrenContract The SuperFrens contract address
    /// @param _startTierId The first tier ID in the set
    /// @param _count How many consecutive NFTs to check (should be 8 for a complete set)
    /// @return isComplete Whether the contract has at least 1 of each NFT in the set
    function hasCompleteNFTSet(
        address _superFrenContract,
        uint256 _startTierId,
        uint256 _count
    )
        external
        view
        returns (bool isComplete)
    {
        isComplete = true;

        for (uint256 i = 0; i < _count; i++) {
            if (ERC1155(_superFrenContract).balanceOf(address(this), _startTierId + i) == 0) {
                isComplete = false;
                break;
            }
        }

        return isComplete;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ERC1155 RECEIVER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Handle receiving a single ERC1155 token
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    )
        external
        returns (bytes4)
    {
        emit NFTReceivedSuperFren(operator, from, id, value);
        return this.onERC1155Received.selector;
    }

    /// @notice Handle receiving multiple ERC1155 tokens
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes memory data
    )
        external
        returns (bytes4)
    {
        emit NFTBatchReceivedSuperFren(operator, from, ids, values);
        return this.onERC1155BatchReceived.selector;
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool isSupported) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EMERGENCY FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emergency withdrawal of ERC20 tokens
    /// @param _token The token address to withdraw
    /// @param _to Recipient address
    /// @param _amount Amount to withdraw
    function emergencyWithdrawERC20(
        address _token,
        address _to,
        uint256 _amount
    )
        external
        onlyRoles(MANAGER_ROLE)
        validAddress(_to)
    {
        (bool success, bytes memory data) =
            _token.call(abi.encodeWithSignature("transfer(address,uint256)", _to, _amount));

        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailedSuperFren();

        emit EmergencyWithdrawalSuperFren(_token, _to, _amount);
    }

    /// @notice Emergency withdrawal of ERC1155 tokens (including SuperFrens)
    /// @param _token The ERC1155 token address
    /// @param _to Recipient address
    /// @param _id Token ID
    /// @param _amount Amount to withdraw
    function emergencyWithdrawERC1155(
        address _token,
        address _to,
        uint256 _id,
        uint256 _amount
    )
        external
        onlyRoles(MANAGER_ROLE)
        validAddress(_to)
    {
        ERC1155(_token).safeTransferFrom(address(this), _to, _id, _amount, "");

        emit EmergencyWithdrawalSuperFren(_token, _to, _amount);
    }

    /// @notice Returns the function selectors for this module
    /// @return Array of function selectors
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](15);
        s[0] = this.addNFTContract.selector;
        s[1] = this.removeNFTContract.selector;
        s[2] = this.registerFunction.selector;
        s[3] = this.removeFunction.selector;
        s[4] = this.executeFunction.selector;
        s[5] = this.claimNFT.selector;
        s[6] = this.batchClaimNFTs.selector;
        s[7] = this.forgeNFT.selector;
        s[8] = this.batchForgeNFTs.selector;
        s[9] = this.getNFTBalance.selector;
        s[10] = this.hasCompleteNFTSet.selector;
        s[11] = this.onERC1155Received.selector;
        s[12] = this.onERC1155BatchReceived.selector;
        s[13] = this.emergencyWithdrawERC20.selector;
        s[14] = this.emergencyWithdrawERC1155.selector;
        return s;
    }
}
