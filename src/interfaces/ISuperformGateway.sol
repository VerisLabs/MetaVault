/// SPDX-License-Identifier: MIT
import { ISuperPositions } from "../interfaces/ISuperPositions.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq
} from "../types/SuperformTypes.sol";

import { SingleXChainMultiVaultWithdraw, SingleXChainSingleVaultWithdraw } from "../types/VaultTypes.sol";

interface ISuperformGateway {
    function getRequestsQueue() external view returns (bytes32[] memory requestIds);

    function recoveryAddress() external view returns (address);

    function grantRoles(address, uint256) external;

    function ADMIN_ROLE() external view returns (uint256);

    function RELAYER_ROLE() external view returns (uint256);

    function setRecoveryAddress(address _newRecoveryAddress) external;

    function superPositions() external view returns (ISuperPositions);

    function notifyRefund(uint256 superformId, uint256 amount) external;

    function notifyBatchRefund(uint256[] calldata superformIds, uint256[] calldata values) external;

    function totalpendingXChainInvests() external view returns (uint256);

    function totalPendingXChainWithdraws() external view returns (uint256);

    function totalPendingXChainDivests() external view returns (uint256);

    function balanceOf(address account, uint256 superformId) external view returns (uint256);

    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        returns (uint256 amount);

    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function divestSingleXChainSingleVault(
        SingleXChainSingleVaultStateReq calldata req,
        bool useReceivers
    )
        external
        payable
        returns (uint256 sharesValue);

    function divestSingleXChainMultiVault(
        SingleXChainMultiVaultStateReq calldata req,
        bool useReceivers
    )
        external
        payable
        returns (uint256 totalAmount);

    function divestMultiXChainSingleVault(
        MultiDstSingleVaultStateReq calldata req,
        bool useReceivers
    )
        external
        payable
        returns (uint256 totalAmount);

    function divestMultiXChainMultiVault(
        MultiDstMultiVaultStateReq calldata req,
        bool useReceivers
    )
        external
        payable
        returns (uint256 totalAmount);

    function liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable;

    function liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        payable;

    function liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        payable;

    function liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory requestedAssetsPerVault
    )
        external
        payable;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool isSupported);
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        external
        returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        external
        returns (bytes4);

    function settleLiquidation(bytes32 key, bool force) external;

    function notifyFailedInvest(uint256 superformId, uint256 refundedAssets) external;

    function getReceiver(bytes32 key) external returns (address receiverAddress);

    function receivers(bytes32 key) external view returns (address receiverAddress);

    function settleDivest(bytes32 key, uint256 assets, bool force) external;

    function previewIdDivestSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds);

    function previewIdDivestSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds);

    function previewIdDivestMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds);

    function previewIdDivestMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds);

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
        returns (bytes32[] memory requestIds);

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
        returns (bytes32[] memory requestIds);

    function previewLiquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        view
        returns (bytes32[] memory requestIds);

    function previewLiquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory totalRequestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds);

    function addFunction(bytes4, address, bool) external;

    function addFunctions(bytes4[] memory, address, bool) external;

    function removeFunction(bytes4) external;

    function removeFunctions(bytes4[] memory) external;

    function requests(bytes32 key) external view returns (address, uint256, address);
}
