// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { ERC1155 } from "solady/tokens/ERC1155.sol";

// Mock contracts for testing
contract MockSuperFrens is ERC1155 {
    // For testing claim functionality
    function claim(address to, uint256 editionId, uint256 tierId, bytes32[] calldata proof) external {
        _mint(to, tierId, 1, "");
    }

    // For testing batch claim functionality
    function batchClaim(
        address to,
        uint256[] calldata editionIds,
        uint256[] calldata tierIds,
        bytes32[][] calldata proofs
    )
        external
    {
        for (uint256 i = 0; i < tierIds.length; i++) {
            _mint(to, tierIds[i], 1, "");
        }
    }

    // For testing forge functionality
    function forge(uint256 tierId) external {
        _burn(msg.sender, tierId, 5);
        _mint(msg.sender, tierId - 1, 1, "");
    }

    // For testing batch forge functionality
    function batchForge(uint256[] calldata tierIds) external {
        for (uint256 i = 0; i < tierIds.length; i++) {
            _burn(msg.sender, tierIds[i], 5);
            _mint(msg.sender, tierIds[i] - 1, 1, "");
        }
    }

    // Required overrides
    function uri(uint256 id) public pure override returns (string memory) {
        return "https://example.com/token/{id}";
    }
}

contract MockExternalContract {
    bool public functionCalled;

    function testFunction(uint256 value) external {
        functionCalled = true;
    }

    function failingFunction() external pure {
        revert("Function failed");
    }
}
