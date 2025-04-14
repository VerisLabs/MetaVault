// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { GatewayBase } from "../common/GatewayBase.sol";
import { ERC20Receiver } from "crosschain/Lib.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw
} from "types/Lib.sol";

/// @title LiquidateSuperform module contract to process metavault crosschain liquidations for users withdrawals
/// @author Unlockd
contract LiquidateSuperform is GatewayBase {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;

    /// @notice Thrown when a request is not found
    error RequestNotFound();
    /// @notice Thrown when minimum balance requirements are not met
    error MinimumBalanceNotMet();
    /// @notice Thrown when an invalid controller address is provided
    error InvalidController();

    /// @notice Emitted when a cross-chain liquidation is initiated
    /// @param controller The address initiating the liquidation
    /// @param superformIds Array of Superform IDs involved
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the liquidation assets receiver contract
    event LiquidateXChain(
        address indexed controller, uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes32 key
    );

    /// @notice Emitted when a request is settled
    event RequestSettled(bytes32 indexed key, address indexed controller, uint256 settledAmount);

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param controller Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    function liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address controller,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        superPositions.safeTransferFrom(address(vault), address(this), superformId, amount, "");
        bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformId));
        _requestsQueue.add(key);
        requestIds[0] = key;
        address assetReceiver = getReceiver(key);
        ERC20Receiver(assetReceiver).setMinExpectedBalance(config.outputAmount);
        SingleXChainSingleVaultStateReq memory params = SingleXChainSingleVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformData: SingleVaultSFData({
                superformId: superformId,
                amount: amount,
                outputAmount: config.outputAmount,
                maxSlippage: config.maxSlippage,
                liqRequest: config.liqRequest,
                permit2data: "",
                hasDstSwap: config.hasDstSwap,
                retain4626: false,
                receiverAddress: assetReceiver,
                receiverAddressSP: assetReceiver,
                extraFormData: ""
            })
        });
        superformRouter.singleXChainSingleVaultWithdraw{ value: config.value }(params);
        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;
        RequestData storage data = requests[key];
        data.requestedAssets = totalRequestedAssets;
        data.controller = controller;
        data.receiverAddress = assetReceiver;
        data.superformIds = superformIds;
        data.requestedAssetsPerVault.push(totalRequestedAssets);

        emit LiquidateXChain(controller, superformIds, totalRequestedAssets, key);
        return requestIds;
    }

    /// @dev Initiates withdrawals from multiple vaults on a single different chain
    /// @param chainId ID of the destination chain
    /// @param superformIds Array of superform IDs to withdraw from
    /// @param amounts Array of share amounts to withdraw from each superform
    /// @param controller Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawals
    function liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address controller,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        uint256 len = superformIds.length;
        bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformIds));
        address assetReceiver = getReceiver(key);
        requestIds[0] = key;
        _requestsQueue.add(key);
        uint256 totalMinExpectedBalance;
        for (uint256 i = 0; i < config.outputAmounts.length; ++i) {
            totalMinExpectedBalance += config.outputAmounts[i];
        }
        ERC20Receiver(assetReceiver).setMinExpectedBalance(totalMinExpectedBalance);
        superPositions.safeBatchTransferFrom(address(vault), address(this), superformIds, amounts, "");
        SingleXChainMultiVaultStateReq memory params = SingleXChainMultiVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformsData: MultiVaultSFData({
                superformIds: superformIds,
                amounts: amounts,
                outputAmounts: config.outputAmounts,
                maxSlippages: config.maxSlippages,
                liqRequests: config.liqRequests,
                permit2data: "",
                hasDstSwaps: config.hasDstSwaps,
                retain4626s: _getEmptyBoolArray(len),
                receiverAddress: assetReceiver,
                receiverAddressSP: assetReceiver,
                extraFormData: ""
            })
        });
        superformRouter.singleXChainMultiVaultWithdraw{ value: config.value }(params);
        RequestData storage data = requests[key];
        data.requestedAssets = totalRequestedAssets;
        data.controller = controller;
        data.receiverAddress = assetReceiver;
        data.superformIds = superformIds;
        data.requestedAssetsPerVault = requestedAssetsPerVault;

        emit LiquidateXChain(controller, superformIds, totalRequestedAssets, key);
        return requestIds;
    }

    /// @dev Initiates withdrawals from a single vault on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param singleVaultDatas Array of SingleVaultSFData structures for each withdrawal
    function liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](singleVaultDatas.length);
        for (uint256 i = 0; i < singleVaultDatas.length;) {
            uint256 superformId = singleVaultDatas[i].superformId;
            uint256[] memory superformIds = new uint256[](1);
            superformIds[0] = superformId;
            bytes32 key = keccak256(
                abi.encode(
                    singleVaultDatas[i].receiverAddress, nonces[singleVaultDatas[i].receiverAddress]++, superformId
                )
            );
            _requestsQueue.add(key);
            requestIds[i] = key;
            address controller = singleVaultDatas[i].receiverAddress;
            address assetReceiver = getReceiver(key);
            ERC20Receiver(assetReceiver).setMinExpectedBalance(singleVaultDatas[i].outputAmount);
            singleVaultDatas[i].receiverAddress = assetReceiver;
            singleVaultDatas[i].receiverAddressSP = assetReceiver;
            RequestData storage data = requests[key];
            data.requestedAssets = totalRequestedAssets[i];
            data.controller = controller;
            data.receiverAddress = assetReceiver;
            data.superformIds = superformIds;
            data.requestedAssetsPerVault.push(totalRequestedAssets[i]);
            superPositions.safeTransferFrom(address(vault), address(this), superformId, singleVaultDatas[i].amount, "");
            emit LiquidateXChain(controller, superformIds, totalRequestedAssets[i], key);
            unchecked {
                ++i;
            }
        }
        MultiDstSingleVaultStateReq memory params =
            MultiDstSingleVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: singleVaultDatas });
        superformRouter.multiDstSingleVaultWithdraw{ value: msg.value }(params);
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    function liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory requestedAssetsPerVault
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](multiVaultDatas.length);
        for (uint256 i = 0; i < multiVaultDatas.length;) {
            uint256[] memory superformIds = multiVaultDatas[i].superformIds;
            address controller = multiVaultDatas[i].receiverAddress;
            bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformIds));
            _requestsQueue.add(key);
            requestIds[i] = key;
            address assetReceiver = getReceiver(key);
            uint256 totalMinExpectedBalance;
            for (uint256 j = 0; j < multiVaultDatas[i].outputAmounts.length; j++) {
                totalMinExpectedBalance += multiVaultDatas[i].outputAmounts[j];
            }
            ERC20Receiver(assetReceiver).setMinExpectedBalance(totalMinExpectedBalance);
            multiVaultDatas[i].receiverAddress = assetReceiver;
            multiVaultDatas[i].receiverAddressSP = assetReceiver;
            RequestData storage data = requests[key];
            data.requestedAssets = totalRequestedAssets[i];
            data.controller = controller;
            data.receiverAddress = assetReceiver;
            data.superformIds = superformIds;
            superPositions.safeBatchTransferFrom(
                address(vault), address(this), superformIds, multiVaultDatas[i].amounts, ""
            );
            data.requestedAssetsPerVault = requestedAssetsPerVault[i];
            emit LiquidateXChain(controller, superformIds, totalRequestedAssets[i], key);
            unchecked {
                ++i;
            }
        }
        MultiDstMultiVaultStateReq memory params =
            MultiDstMultiVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: multiVaultDatas });
        superformRouter.multiDstMultiVaultWithdraw{ value: msg.value }(params);
    }

    /// @notice Settles a cross-chain liquidation by processing received assets
    /// @dev Pulls assets from the receiver contract and fulfills the settlement in the vault.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// @param key identifier of the receiver contract
    function settleLiquidation(bytes32 key, bool force) external onlyRoles(RELAYER_ROLE) {
        if (!_requestsQueue.contains(key)) revert RequestNotFound();

        RequestData memory data = requests[key];
        if (data.controller == address(0)) revert InvalidController();

        ERC20Receiver receiverContract = ERC20Receiver(getReceiver(key));
        uint256 settledAssets = receiverContract.balance();

        _requestsQueue.remove(key);

        if (!force) {
            if (receiverContract.balance() < receiverContract.minExpectedBalance()) {
                revert MinimumBalanceNotMet();
            }
        }

        receiverContract.pull(settledAssets);
        asset.safeTransfer(address(vault), settledAssets);
        vault.fulfillSettledRequest(data.controller, data.requestedAssets, settledAssets);
        emit RequestSettled(key, data.controller, settledAssets);
    }

    function previewLiquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        bytes32 key = keccak256(abi.encode(receiver, nonces[receiver], superformId));
        requestIds[0] = key;
        return requestIds;
    }

    function previewLiquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        bytes32 key = keccak256(abi.encode(receiver, nonces[receiver], superformIds));
        requestIds[0] = key;
        return requestIds;
    }

    function previewLiquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](singleVaultDatas.length);
        for (uint256 i = 0; i < singleVaultDatas.length;) {
            uint256 superformId = singleVaultDatas[i].superformId;
            bytes32 key = keccak256(
                abi.encode(
                    singleVaultDatas[i].receiverAddress, nonces[singleVaultDatas[i].receiverAddress] + i, superformId
                )
            );
            requestIds[i] = key;
            unchecked {
                ++i;
            }
        }
        return requestIds;
    }

    function previewLiquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory totalRequestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](multiVaultDatas.length);
        for (uint256 i = 0; i < multiVaultDatas.length;) {
            uint256[] memory superformIds = multiVaultDatas[i].superformIds;
            bytes32 key = keccak256(
                abi.encode(
                    multiVaultDatas[i].receiverAddress, nonces[multiVaultDatas[i].receiverAddress] + i, superformIds
                )
            );
            requestIds[i] = key;
            unchecked {
                ++i;
            }
        }
        return requestIds;
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](9);
        s[0] = this.liquidateSingleXChainSingleVault.selector;
        s[1] = this.liquidateSingleXChainMultiVault.selector;
        s[2] = this.liquidateMultiDstSingleVault.selector;
        s[3] = this.liquidateMultiDstMultiVault.selector;

        s[4] = this.settleLiquidation.selector;

        s[5] = this.previewLiquidateSingleXChainSingleVault.selector;
        s[6] = this.previewLiquidateSingleXChainMultiVault.selector;
        s[7] = this.previewLiquidateMultiDstSingleVault.selector;
        s[8] = this.previewLiquidateMultiDstMultiVault.selector;
        return s;
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) private pure returns (bool[] memory) {
        return new bool[](len);
    }
}
