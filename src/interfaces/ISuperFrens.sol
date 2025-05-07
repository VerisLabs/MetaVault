// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title ISuperFrens
/// @notice interface for the SuperFrens contract
/// @author Zeropoint Labs
interface ISuperFrens {
    //////////////////////////////////////////////////////////////
    //                      STRUCTS                             //
    //////////////////////////////////////////////////////////////
    struct Supply {
        uint256 availableToMint;
        uint256 currentSupply;
    }

    //////////////////////////////////////////////////////////////
    //                     ERRORS                               //
    //////////////////////////////////////////////////////////////

    error INVALID_CLAIM();

    error INVALID_FORGE_TIER();

    error INVALID_BATCH_REQ();

    error INVALID_MERKLE_ROOT();

    error INVALID_RECEIVER();

    error MERKLE_ROOT_NOT_SET();

    error MERKLE_ROOT_ALREADY_SET();

    error PREVIOUS_EDITION_NOT_SET();

    error NO_SUPERFRENS_AVAILABLE_TO_MINT();

    error URI_FROZEN();

    error ZERO_ARR_LENGTH();

    //////////////////////////////////////////////////////////////
    //                      EVENTS                              //
    //////////////////////////////////////////////////////////////

    /// @dev Emitted when tokens are claimed.
    event TokensClaimed(address indexed claimer, address indexed receiver, uint256 indexed editionId, uint256 tierId);

    /// @dev Emitted when tokens forged
    event TokensForged(address indexed forger, uint256 indexed tierId, uint256 indexed forgeId);

    /// @dev Emitted when a new edition is set.
    event EditionSet(uint256 indexed editionid, bytes32 merkleRoot);

    /// @dev Emitted when the collection base uri is updated
    event BaseURIUpdated(string oldURI, string newURI, bool frozen);

    //////////////////////////////////////////////////////////////
    //              EXTERNAL WRITE FUNCTIONS                    //
    //////////////////////////////////////////////////////////////

    /// @notice allows owner to set the merkle root for the next edition
    /// @param editionId_ is the edition identifier
    /// @param root_ is the merkle root for that edition generated offchain
    /// @dev [gas-opt]: function is payable to avoid msg.value checks
    function setEdition(uint256 editionId_, bytes32 root_) external payable;

    /// @notice allows owner to update the collection uri
    /// @param uri_ is the new base uri; eg., if id uri is https://www.base.com/1, then base uri https://www.base.com/
    /// @param freeze_ indicates whether this is the final update
    /// @dev [gas-opt]: function is payable to avoid msg.value checks
    function setUri(string memory uri_, bool freeze_) external payable;

    /// @notice lets an account claim a given quantity of ERC1155 tokens.
    /// @param receiver_ is the receiver of the tokens to claim.
    /// @param editionId_ is the specific edition to claim
    /// @param tierId_ is the tier id to claim
    /// @param proof_ the merkle proof
    function claim(address receiver_, uint256 editionId_, uint256 tierId_, bytes32[] calldata proof_) external;

    /// @notice is a batching version of claim()
    function batchClaim(
        address receiver_,
        uint256[] calldata editionIds_,
        uint256[] calldata tierIds_,
        bytes32[][] calldata proofs_
    )
        external;

    /// @notice allows users to forge 5 NFTs of same tier for a higher tier
    /// @param tierId_ is the tier to forge
    function forge(uint256 tierId_) external;

    /// @notice is a batching version of forge
    function batchForge(uint256[] calldata tierIds_) external;

    //////////////////////////////////////////////////////////////
    //              EXTERNAL VIEW FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    /// @notice helps validate if the claim is valid
    /// @param claimer_ is the address of the claiming wallet
    /// @param editionId_ is the edition identifier (total 12 editions)
    /// @param tierId_ is the tier identifier within a specific edition (eg. ETHREAL, MYTHIC, etc.,)
    /// @param proof_ is the merkle proof
    /// @dev returns false even if proof is valid and user already claimed his NFT
    function verifyClaim(
        address claimer_,
        uint256 editionId_,
        uint256 tierId_,
        bytes32[] calldata proof_
    )
        external
        view
        returns (bool valid);

    /// @notice returns the uri for individual token ids
    /// @param tokenId_ is the unique id of the token
    /// @dev returns the final uri of the id
    function tokenURI(uint256 tokenId_) external view returns (string memory);
}
