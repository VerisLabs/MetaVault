// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { MockERC20 } from "./MockERC20.sol";

// Mock Bridge Target that simulates an actual token transfer
contract MockBridgeTarget {
    bool public wasCalled;

    function mockBridgeFunction(address token, address receiver, uint256 amount) public {
        wasCalled = true;
        // Simulate transferring tokens to an external address
        MockERC20(token).transferFrom(msg.sender, receiver, amount);
    }

    fallback() external payable {
        wasCalled = true;
    }

    receive() external payable {
        wasCalled = true;
    }
}

contract MockFailureBridgeTarget {
    function mockFailBridgeFunction() public pure {
        revert("Bridge operation failed");
    }
}

// Mock Bridge Target that simulates an actual token transfer
contract MockBridgeTargetNoTransfer {
    bool public wasCalled;

    function mockBridgeFunction(address token, address receiver, uint256 amount) public {
        // Not transferring the tokens
        wasCalled = true;
    }

    fallback() external payable {
        wasCalled = true;
    }

    receive() external payable {
        wasCalled = true;
    }
}
