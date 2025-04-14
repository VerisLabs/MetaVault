/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBridgeValidator {
    function decodeAmountIn(
        bytes calldata txData_,
        bool genericSwapDisallowed_
    )
        external
        view
        returns (uint256 amount_);
}
