// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { Test } from "forge-std/Test.sol";
import { ISuperformRewardsDistributor } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract MockSwapHandler is Test {
    using SafeTransferLib for address;

    bool _revert = false;

    // Simple swap function that ignores the input token and just transfers output tokens
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256) {
        if (_revert) revert();

        // Just transfer some output tokens to the caller
        // For simplicity, we'll transfer 1:1 (amountIn = amountOut)
        uint256 amountOut = amountIn / 10 ** 12; // Convert from 18 decimals to 6 decimals

        // Transfer the output tokens to the caller
        deal(tokenOut, msg.sender, tokenOut.balanceOf(msg.sender) + amountOut);

        return amountOut;
    }

    function setRevert(bool r) public {
        _revert = r;
    }
}
