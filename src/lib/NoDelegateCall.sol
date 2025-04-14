// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Prevents delegatecall to a contract
/// @notice Base contract that provides a modifier for preventing delegatecall to methods in a child contract
abstract contract NoDelegateCall {
    error DelegateCallNotAllowed();

    constructor() {
        // Immutables are computed in the init code of the contract, and then inlined into the deployed bytecode.
        // In other words, this variable won't change when it's checked at runtime.
        // 0xa203c8cf3ff5695cb1e2caee14320584cc3e0e4b039b8fa3ae49b5e0568c699d = keccak256("NoDelegateCall::original")
        assembly {
            sstore(0xa203c8cf3ff5695cb1e2caee14320584cc3e0e4b039b8fa3ae49b5e0568c699d, address())
        }
    }

    /// @dev Private method is used instead of inlining into modifier because modifiers are copied into each method,
    ///     and the use of immutable means the address bytes are copied in every place the modifier is used.
    function checkNotDelegateCall() private view {
        if (address(this) != _getOriginalAddress()) revert DelegateCallNotAllowed();
    }

    /// @dev Private method is used instead of inlining into modifier because modifiers are copied into each method,
    function _getOriginalAddress() private view returns (address original) {
        assembly {
            original := sload(0xa203c8cf3ff5695cb1e2caee14320584cc3e0e4b039b8fa3ae49b5e0568c699d)
        }
    }

    /// @notice Prevents delegatecall into the modified method
    modifier noDelegateCall() {
        checkNotDelegateCall();
        _;
    }
}
