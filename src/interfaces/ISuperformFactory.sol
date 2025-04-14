// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface ISuperformFactory {
    enum PauseStatus {
        NON_PAUSED,
        PAUSED
    }

    event FormImplementationAdded(
        address indexed formImplementation, uint256 indexed formImplementationId, uint8 indexed formStateRegistryId
    );

    event SuperformCreated(
        uint256 indexed formImplementationId, address indexed vault, uint256 indexed superformId, address superform
    );

    event SuperRegistrySet(address indexed superRegistry);

    event FormImplementationPaused(uint256 indexed formImplementationId, PauseStatus indexed paused);

    function getFormCount() external view returns (uint256 forms_);

    function getSuperformCount() external view returns (uint256 superforms_);

    function getFormImplementation(uint32 formImplementationId_) external view returns (address formImplementation_);

    function getFormStateRegistryId(uint32 formImplementationId_) external view returns (uint8 stateRegistryId_);

    function isFormImplementationPaused(uint32 formImplementationId_) external view returns (bool paused_);

    function getSuperform(uint256 superformId_)
        external
        pure
        returns (address superform_, uint32 formImplementationId_, uint64 chainId_);

    function isSuperform(uint256 superformId_) external view returns (bool isSuperform_);

    function getAllSuperformsFromVault(address vault_)
        external
        view
        returns (uint256[] memory superformIds_, address[] memory superforms_);

    function addFormImplementation(
        address formImplementation_,
        uint32 formImplementationId_,
        uint8 formStateRegistryId_
    )
        external;

    function createSuperform(
        uint32 formImplementationId_,
        address vault_
    )
        external
        returns (uint256 superformId_, address superform_);

    function stateSyncBroadcast(bytes memory data_) external payable;

    function changeFormImplementationPauseStatus(
        uint32 formImplementationId_,
        PauseStatus status_,
        bytes memory extraData_
    )
        external
        payable;
}
