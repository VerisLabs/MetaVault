// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC7540ProcessRedeemBase } from "./common/ERC7540ProcessRedeemBase.sol";

import { ProcessRedeemRequestParams } from "types/Lib.sol";

/// @title ERC7540Engine
/// @notice Implementation of a ERC4626 multi-vault deposit liquidity engine with cross-chain functionalities
/// @dev Extends ERC7540ProcessRedeemBase contract and implements advanced redeem request processing
contract ERC7540Engine is ERC7540ProcessRedeemBase {
    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillSettledRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @notice Processes a redemption request for a given controller
    /// @dev This function is restricted to the RELAYER_ROLE and handles asynchronous processing of redemption requests,
    /// including cross-chain withdrawals
    /// @param params redeem request parameters
    function processRedeemRequest(ProcessRedeemRequestParams calldata params)
        external
        payable
        onlyRoles(RELAYER_ROLE)
        nonReentrant
    {
        // Retrieve the pending redeem request for the specified controller
        // This request may involve cross-chain withdrawals from various ERC4626 vaults

        // Process the redemption request asynchronously
        // Parameters:
        // 1. pendingRedeemRequest(controller): Fetches the pending shares
        // 2. controller: The address initiating the redemption (used as both 'from' and 'to')
        _processRedeemRequest(
            ProcessRedeemRequestConfig(
                params.shares == 0 ? pendingRedeemRequest(params.controller) : params.shares,
                params.controller,
                params.sXsV,
                params.sXmV,
                params.mXsV,
                params.mXmV
            )
        );
        // Note: After processing, the redeemed assets are held by this contract
        // The user can later claim these assets using `redeem` or `withdraw`
    }

    /// @notice Fulfills a settled cross-chain redemption request
    /// @dev Called by the gateway contract when cross-chain assets have been received.
    /// Converts the requested assets to shares and fulfills the redemption request.
    /// Only callable by the gateway contract.
    /// @param controller The address that initiated the redemption request
    /// @param requestedAssets The original amount of assets requested
    /// @param fulfilledAssets The actual amount of assets received after bridging
    function fulfillSettledRequest(address controller, uint256 requestedAssets, uint256 fulfilledAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        uint256 shares = convertToShares(requestedAssets);
        pendingProcessedShares[controller] = _sub0(pendingProcessedShares[controller], shares);
        _fulfillRedeemRequest(shares, fulfilledAssets, controller, false);
        emit FulfillSettledRequest(controller, shares, fulfilledAssets);
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](3);
        s[0] = this.processRedeemRequest.selector;
        s[1] = this.fulfillSettledRequest.selector;
        s[2] = this.setDustThreshold.selector;
        return s;
    }
}
