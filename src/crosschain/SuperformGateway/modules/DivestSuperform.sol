// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { GatewayBase } from "../common/GatewayBase.sol";
import { ERC20Receiver } from "crosschain/Lib.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq,
    VaultData,
    VaultLib
} from "types/Lib.sol";

/// @title DivestSuperform module contract to divest from crosschain ERC4626 vaults using Superform
/// @author Unlockd
/// @notice All this actions are restricted to the portfolio manager role
contract DivestSuperform is GatewayBase {
    using VaultLib for VaultData;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;

    /// @notice Thrown when total amounts do not match
    error TotalAmountMismatch();

    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();

    /// @notice Thrown when attempting to interact with an unlisted vault
    error VaultNotListed();

    /// @notice Thrown when an invalid receiver address is provided
    error InvalidReceiver();

    /// @notice Thrown when an invalid superform ID is provided
    error InvalidSuperformId();

    /// @notice Emitted when pending divest amount is updated
    event PendingDivestUpdated(uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when a cross-chain divestment is initiated
    /// @param superformIds Array of Superform IDs being divested
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the divest assets receiver contract
    event DivestXChain(uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes32 key);

    /// @notice Emitted when a divestment fails and SuperPositions are refunded
    /// @param superformId The ID of the Superform being refunded
    /// @param value The amount of SuperPositions being refunded
    /// @param key The unique identifier for the divest request
    event DivestRefunded(uint256 indexed superformId, uint256 indexed value, bytes32 indexed key);

    /// @notice Emitted when a new request is created
    event RequestCreated(bytes32 indexed key, address indexed controller, uint256[] superformIds);

    /// @notice Divests assets from a single vault on a different chain
    /// @dev Transfers Superform NFTs from vault to this contract and initiates withdrawal
    /// @param req The cross-chain withdrawal request parameters
    /// @return sharesValue The value of shares being withdrawn in terms of underlying assets
    function divestSingleXChainSingleVault(
        SingleXChainSingleVaultStateReq memory req,
        bool useReceivers
    )
        external
        payable
        onlyVault
        refundGas
        returns (uint256 sharesValue)
    {
        uint256 superformId = req.superformData.superformId;
        if (superformId == 0) revert InvalidSuperformId();

        bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformId));
        _requestsQueue.add(key);

        address receiver;
        if (useReceivers) {
            receiver = getReceiver(key);
            if (receiver == address(0)) revert InvalidReceiver();
            ERC20Receiver(receiver).setMinExpectedBalance(req.superformData.outputAmount);
        } else {
            receiver = req.superformData.receiverAddress;
        }

        VaultData memory vaultObj = vault.getVault(superformId);
        if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

        if (useReceivers) {
            req.superformData.receiverAddress = receiver;
            req.superformData.receiverAddressSP = receiver;
        }

        // Update the vault's internal accounting
        sharesValue = vaultObj.convertToAssets(req.superformData.amount, asset, true);

        if (sharesValue == 0) revert InvalidAmount();

        uint256 oldAmount = totalPendingXChainDivests;
        totalPendingXChainDivests += sharesValue;
        emit PendingDivestUpdated(oldAmount, totalPendingXChainDivests);

        superPositions.safeTransferFrom(address(vault), address(this), superformId, req.superformData.amount, "");

        superformRouter.singleXChainSingleVaultWithdraw{ value: msg.value }(req);

        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;

        RequestData storage data = requests[key];
        data.controller = address(vault);
        data.receiverAddress = receiver;
        data.superformIds = superformIds;
        data.requestedAssets = sharesValue;
        data.requestedAssetsPerVault.push(sharesValue);
        data.hasReceiver = useReceivers;

        emit RequestCreated(key, address(vault), superformIds);
        emit DivestXChain(superformIds, sharesValue, key);

        return sharesValue;
    }

    /// @notice Divests assets from multiple vaults on a single chain
    /// @dev Batch transfers Superform NFTs and initiates withdrawals for multiple vaults
    /// @param req The cross-chain multi-vault withdrawal request parameters
    /// @param useReceivers Whether to use receiver contracts for the divest
    /// @return totalAmount The total value of shares being withdrawn
    function divestSingleXChainMultiVault(
        SingleXChainMultiVaultStateReq memory req,
        bool useReceivers
    )
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (req.superformsData.superformIds.length == 0) revert InvalidAmount();
        if (req.superformsData.superformIds.length != req.superformsData.amounts.length) revert TotalAmountMismatch();

        bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, req.superformsData.superformIds));
        RequestData storage data = requests[key];
        uint256 totalExpectedAmount;
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];
            if (superformId == 0) revert InvalidSuperformId();

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

            uint256 amount = vaultObj.convertToAssets(req.superformsData.amounts[i], asset, true);
            if (amount == 0) revert InvalidAmount();

            totalExpectedAmount += req.superformsData.outputAmounts[i];
            data.requestedAssetsPerVault.push(amount);
            // Update the vault's internal accounting
            totalAmount += amount;
        }

        _requestsQueue.add(key);

        address receiver;
        if (useReceivers) {
            receiver = getReceiver(key);
            if (receiver == address(0)) revert InvalidReceiver();
            ERC20Receiver(receiver).setMinExpectedBalance(totalExpectedAmount);
        } else {
            receiver = req.superformsData.receiverAddress;
        }

        data.controller = address(vault);
        data.receiverAddress = receiver;
        data.superformIds = req.superformsData.superformIds;
        data.requestedAssets = totalAmount;
        data.hasReceiver = useReceivers;

        if (useReceivers) {
            req.superformsData.receiverAddress = receiver;
            req.superformsData.receiverAddressSP = receiver;
        }

        superPositions.safeBatchTransferFrom(
            address(vault), address(this), req.superformsData.superformIds, req.superformsData.amounts, ""
        );

        superformRouter.singleXChainMultiVaultWithdraw{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;

        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
        emit RequestCreated(key, address(vault), req.superformsData.superformIds);
        emit DivestXChain(req.superformsData.superformIds, totalAmount, key);
    }

    /// @notice Divests assets from a single vault type across multiple chains
    /// @dev Processes withdrawals for the same vault type on different chains
    /// @param req The multi-chain single vault withdrawal request parameters
    /// @param useReceivers Whether to use receiver contracts for the divest
    /// @return totalAmount The total value of shares being withdrawn
    function divestMultiXChainSingleVault(
        MultiDstSingleVaultStateReq memory req,
        bool useReceivers
    )
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;

            uint256[] memory superformIds = new uint256[](1);
            superformIds[0] = superformId;

            bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformId));
            _requestsQueue.add(key);

            address receiver;
            if (useReceivers) {
                receiver = getReceiver(key);
                if (receiver == address(0)) revert InvalidReceiver();
                ERC20Receiver(receiver).setMinExpectedBalance(req.superformsData[i].outputAmount);
            } else {
                receiver = req.superformsData[i].receiverAddress;
            }

            // Retrieve the vault data for the target vault
            VaultData memory vaultObj = vault.getVault(superformId);
            // Cant invest in a vault that is not in the portfolio
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
            uint256 amount = vaultObj.convertToAssets(req.superformsData[i].amount, asset, true);

            totalAmount += amount;

            RequestData storage data = requests[key];
            data.controller = address(vault);
            data.receiverAddress = receiver;
            data.superformIds = superformIds;
            data.requestedAssets = amount;
            data.requestedAssetsPerVault.push(amount);
            data.hasReceiver = useReceivers;

            if (useReceivers) {
                req.superformsData[i].receiverAddress = receiver;
                req.superformsData[i].receiverAddressSP = receiver;
            }

            superPositions.safeTransferFrom(
                address(vault), address(this), superformId, req.superformsData[i].amount, ""
            );

            emit RequestCreated(key, address(vault), superformIds);
            emit DivestXChain(superformIds, amount, key);

            unchecked {
                ++i;
            }
        }

        superformRouter.multiDstSingleVaultWithdraw{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;
        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
        return totalAmount;
    }

    /// @notice Divests assets from multiple vaults across multiple chains
    /// @dev Processes withdrawals for different vault types across multiple chains
    /// @param req The multi-chain multi-vault withdrawal request parameters
    /// @param useReceivers Whether to use receiver contracts for the divest
    /// @return totalAmount The total value of shares being withdrawn
    function divestMultiXChainMultiVault(
        MultiDstMultiVaultStateReq memory req,
        bool useReceivers
    )
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;
            uint256 totalChainAmount;

            uint256 totalExpectedAmount;
            bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformIds));
            RequestData storage data = requests[key];
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];
                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);

                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

                uint256 amount = vaultObj.convertToAssets(amounts[j], asset, true);
                data.requestedAssetsPerVault.push(amount);
                totalExpectedAmount += req.superformsData[i].outputAmounts[j];
                totalAmount += amount;
                totalChainAmount += amount;
            }

            _requestsQueue.add(key);

            address receiver;
            if (useReceivers) {
                receiver = getReceiver(key);
                if (receiver == address(0)) revert InvalidReceiver();
                ERC20Receiver(receiver).setMinExpectedBalance(totalExpectedAmount);
            } else {
                receiver = req.superformsData[i].receiverAddress;
            }

            data.controller = address(vault);
            data.receiverAddress = receiver;
            data.superformIds = superformIds;
            data.requestedAssets = totalChainAmount;
            data.hasReceiver = useReceivers;

            if (useReceivers) {
                req.superformsData[i].receiverAddress = receiver;
                req.superformsData[i].receiverAddressSP = receiver;
            }

            superPositions.safeBatchTransferFrom(address(vault), address(this), superformIds, amounts, "");

            emit RequestCreated(key, address(vault), superformIds);
            emit DivestXChain(superformIds, totalChainAmount, key);
        }

        superformRouter.multiDstMultiVaultWithdraw{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;

        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
        return totalAmount;
    }

    /// @notice Internal function to handle refund of SuperPositions
    /// @param key The key of the request
    /// @param superformId The ID of the Superform position being refunded
    /// @param value The amount of SuperPositions being refunded
    /// @param vaultRequestedAssets The amount of assets requested for this vault
    function _handleRefund(bytes32 key, uint256 superformId, uint256 value, uint256 vaultRequestedAssets) internal {
        if (requests[key].controller == address(vault)) {
            totalPendingXChainDivests -= vaultRequestedAssets;
        }
        requests[key].requestedAssets -= vaultRequestedAssets;

        superPositions.safeTransferFrom(msg.sender, address(this), superformId, value, "");
        superPositions.safeTransferFrom(
            address(this),
            address(vault),
            superformId,
            value,
            abi.encode(
                requests[key].controller == address(vault) ? address(0) : requests[key].controller, vaultRequestedAssets
            )
        );

        emit DivestRefunded(superformId, value, key);
    }

    /// @notice Handles refunds of SuperPositions when a cross-chain divestment fails
    /// @dev This function is called by the ERC20Receiver contract when a divestment fails and SuperPositions need to be
    /// returned
    ///      The function verifies the caller is a valid receiver, updates pending divest amounts, and transfers the
    /// SuperPositions back to the vault
    /// @param superformId The ID of the Superform position being refunded
    /// @param value The amount of SuperPositions being refunded
    function notifyRefund(uint256 superformId, uint256 value) external {
        bytes32 key = ERC20Receiver(msg.sender).key();
        if (requests[key].receiverAddress != msg.sender) revert();
        RequestData memory req = requests[key];
        uint256 currentExpectedBalance = ERC20Receiver(msg.sender).minExpectedBalance();

        uint256 vaultIndex;
        for (uint256 i = 0; i < req.superformIds.length; ++i) {
            if (req.superformIds[i] == superformId) {
                vaultIndex = i;
                break;
            }
        }
        uint256 vaultRequestedAssets = req.requestedAssetsPerVault[vaultIndex];

        _handleRefund(key, superformId, value, vaultRequestedAssets);

        // Only remove from queue if ALL superformIds have been refunded
        // We can check this by seeing if remaining requestedAssets is zero
        if (requests[key].requestedAssets == 0) {
            _requestsQueue.remove(key);
        }

        ERC20Receiver(msg.sender).setMinExpectedBalance(_sub0(currentExpectedBalance, vaultRequestedAssets));
    }

    /// @notice Handles batch refunds of SuperPositions when a cross-chain divestment fails
    /// @dev This function is called by the ERC20Receiver contract when multiple divestments fail and SuperPositions
    /// need to be
    /// returned
    ///      The function verifies the caller is a valid receiver, updates pending divest amounts, and transfers the
    /// SuperPositions back to the vault
    /// @param superformIds Array of Superform position IDs being refunded
    /// @param values Array of SuperPosition amounts being refunded
    function notifyBatchRefund(uint256[] calldata superformIds, uint256[] calldata values) external {
        bytes32 key = ERC20Receiver(msg.sender).key();
        if (requests[key].receiverAddress != msg.sender) revert();
        RequestData memory req = requests[key];
        uint256 currentExpectedBalance = ERC20Receiver(msg.sender).minExpectedBalance();
        uint256 totalVaultRequestedAssets;

        for (uint256 j = 0; j < superformIds.length; ++j) {
            uint256 vaultIndex;
            for (uint256 i = 0; i < req.superformIds.length; ++i) {
                if (req.superformIds[i] == superformIds[j]) {
                    vaultIndex = i;
                    break;
                }
            }
            uint256 vaultRequestedAssets = req.requestedAssetsPerVault[vaultIndex];
            totalVaultRequestedAssets += vaultRequestedAssets;

            _handleRefund(key, superformIds[j], values[j], vaultRequestedAssets);
        }

        // Only remove from queue if ALL superformIds have been refunded
        if (requests[key].requestedAssets == 0) {
            _requestsQueue.remove(key);
        }
        ERC20Receiver(msg.sender).setMinExpectedBalance(_sub0(currentExpectedBalance, totalVaultRequestedAssets));
    }

    /// @notice Settles a cross-chain divestment by processing received assets
    /// @dev Pulls assets from the receiver contract and updates the vault's state.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// For each Superform ID involved, notifies the vault of the settlement.
    /// @param key Identifier of the receiver contract
    function settleDivest(bytes32 key, uint256 assets, bool force) external onlyRoles(RELAYER_ROLE) {
        if (!_requestsQueue.contains(key)) revert();
        RequestData memory data = requests[key];
        _requestsQueue.remove(key);

        if (data.controller != address(vault)) revert();

        uint256 settledAssets;
        if (data.hasReceiver) {
            ERC20Receiver receiverContract = ERC20Receiver(getReceiver(key));
            if (!force) {
                if (receiverContract.balance() < receiverContract.minExpectedBalance()) revert();
            }
            settledAssets = receiverContract.balance();
            receiverContract.pull(settledAssets);
        } else {
            settledAssets = assets;
            asset.safeTransferFrom(msg.sender, address(this), settledAssets);
        }

        uint256 requestedAssets = data.requestedAssets;
        totalPendingXChainDivests = _sub0(totalPendingXChainDivests, requestedAssets);
        asset.safeTransfer(address(vault), settledAssets);
        vault.settleXChainDivest(settledAssets);
    }

    function previewIdDivestSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        uint256 superformId = req.superformData.superformId;
        requestIds[0] = keccak256(abi.encode(address(vault), nonces[address(vault)], superformId));
        return requestIds;
    }

    function previewIdDivestSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode(address(vault), nonces[address(vault)], req.superformsData.superformIds));
        return requestIds;
    }

    function previewIdDivestMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](req.superformsData.length);
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            requestIds[i] = keccak256(abi.encode(address(vault), nonces[address(vault)] + i, superformId));
        }
    }

    function previewIdDivestMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](req.superformsData.length);
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            requestIds[i] = keccak256(abi.encode(address(vault), nonces[address(vault)] + i, superformIds));
        }
    }

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](10);
        s[0] = this.divestSingleXChainSingleVault.selector;
        s[1] = this.divestSingleXChainMultiVault.selector;
        s[2] = this.divestMultiXChainSingleVault.selector;
        s[3] = this.divestMultiXChainMultiVault.selector;

        s[4] = this.notifyRefund.selector;
        s[5] = this.settleDivest.selector;

        s[6] = this.previewIdDivestSingleXChainSingleVault.selector;
        s[7] = this.previewIdDivestMultiXChainSingleVault.selector;
        s[8] = this.previewIdDivestSingleXChainMultiVault.selector;
        s[9] = this.previewIdDivestMultiXChainMultiVault.selector;
        return s;
    }
}
