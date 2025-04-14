// SPDX-License-Identifier: GPL-2.0-or-later

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { PendingRoot } from "types/Lib.sol";

/// @title RewardDistributor
/// @author Unlockd
/// @notice Adapted from Morpho's UniversalRewardDistributor:
/// https://github.com/morpho-org/universal-rewards-distributor/blob/main/src/UniversalRewardsDistributor.sol
contract RewardDistributor is OwnableRoles {
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error RootAlreadyPending();
    error ProofInvalidOrExpired();
    error RootNotSet();
    error NoPendingRoot();
    error AlreadyPending();
    error TimelockNotExpired();
    error ClaimableTooLow();
    error UnauthorizedRootChange();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event PendingRootSet(address by, bytes32 indexed newRoot, bytes32 newIpfsHash);
    event PendingRootRevoked(address by);
    event Claimed(address indexed account, address indexed reward, uint256 amount);
    event RootSet(bytes32 indexed newRoot, bytes32 newIpfsHash);
    event TimelockSet(uint256 newTimelock);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Role identifier for emergency admin privileges
    uint256 public constant UPDATER_ROLE = _ROLE_0;

    /// @notice The merkle root of this distribution.
    bytes32 public root;

    /// @notice The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    bytes32 public ipfsHash;

    /// @notice The `amount` of `reward` token already claimed by `account`.
    mapping(address account => mapping(address reward => uint256 amount)) public claimed;

    /// @notice The addresses that can update the merkle root.
    mapping(address => bool) public isUpdater;

    /// @notice The timelock related to root updates.
    uint256 public timelock;

    /// @notice The pending root of the distribution.
    /// @dev If the pending root is set, the root can be updated after the timelock has expired.
    /// @dev The pending root is skipped if the timelock is set to 0.
    PendingRoot public pendingRoot;

    constructor(address owner, address updater) {
        _initializeOwner(owner);
        _grantRoles(updater, UPDATER_ROLE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EXTERNAL                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Submits a new merkle root.
    /// @param newRoot The new merkle root.
    /// @param newIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function submitRoot(bytes32 newRoot, bytes32 newIpfsHash) external onlyRoles(UPDATER_ROLE) {
        if (newRoot == pendingRoot.root || newIpfsHash == pendingRoot.ipfsHash) {
            revert AlreadyPending();
        }
        pendingRoot = PendingRoot({ root: newRoot, ipfsHash: newIpfsHash, validAt: block.timestamp + timelock });
        emit PendingRootSet(msg.sender, newRoot, newIpfsHash);
    }

    /// @notice Accepts and sets the current pending merkle root.
    /// @dev This function can only be called after the timelock has expired.
    /// @dev Anyone can call this function.
    function acceptRoot() external {
        if (pendingRoot.validAt == 0) revert NoPendingRoot();
        if (block.timestamp < pendingRoot.validAt) revert TimelockNotExpired();
        _setRoot(pendingRoot.root, pendingRoot.ipfsHash);
    }

    /// @notice Revokes the pending root.
    /// @dev Can be frontrunned with `acceptRoot` in case the timelock has passed.
    function revokePendingRoot() external onlyRoles(UPDATER_ROLE) {
        if (pendingRoot.validAt == 0) revert NoPendingRoot();
        delete pendingRoot;
        emit PendingRootRevoked(msg.sender);
    }

    /// @notice Claims rewards.
    /// @param account The address to claim rewards for.
    /// @param reward The address of the reward token.
    /// @param claimable The overall claimable amount of token rewards.
    /// @param proof The merkle proof that validates this claim.
    /// @return amount The amount of reward token claimed.
    /// @dev Anyone can claim rewards on behalf of an account.
    function claim(
        address account,
        address reward,
        uint256 claimable,
        bytes32[] calldata proof
    )
        external
        returns (uint256 amount)
    {
        if (root == bytes32(0)) revert RootNotSet();
        if (
            !MerkleProofLib.verifyCalldata(
                proof, root, keccak256(bytes.concat(keccak256(abi.encode(account, reward, claimable))))
            )
        ) {
            revert ProofInvalidOrExpired();
        }

        if (claimable <= claimed[account][reward]) revert ClaimableTooLow();

        amount = claimable - claimed[account][reward];

        claimed[account][reward] = claimable;

        reward.safeTransfer(account, amount);

        emit Claimed(account, reward, amount);
    }

    /// @notice Forces update the root of a given distribution (bypassing the timelock).
    /// @param newRoot The new merkle root.
    /// @param newIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    /// @dev This function can only be called by the owner of the distribution or by updaters if there is no timelock.
    /// @dev Set to bytes32(0) to remove the root.
    function setRoot(bytes32 newRoot, bytes32 newIpfsHash) external onlyOwner {
        if (timelock != 0) revert UnauthorizedRootChange();
        _setRoot(newRoot, newIpfsHash);
    }

    /// @notice Sets the timelock of a given distribution.
    /// @param newTimelock The new timelock.
    /// @dev This function can only be called by the owner of the distribution.
    /// @dev The timelock modification are not applicable to the pending values.
    function setTimelock(uint256 newTimelock) external onlyOwner {
        _setTimelock(newTimelock);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           INTERNAL                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sets the `root` and `ipfsHash` to `newRoot` and `newIpfsHash`.
    /// @dev Deletes the pending root.
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function _setRoot(bytes32 newRoot, bytes32 newIpfsHash) internal {
        root = newRoot;
        ipfsHash = newIpfsHash;

        delete pendingRoot;

        emit RootSet(newRoot, newIpfsHash);
    }

    /// @dev Sets the `timelock` to `newTimelock`.
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;

        emit TimelockSet(newTimelock);
    }
}
