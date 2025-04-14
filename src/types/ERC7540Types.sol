// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

/// @title ERC7540 Request Type
/// @notice Represents a request in the ERC7540 standard
/// @dev This type is a simple wrapper around a uint256 value
type ERC7540_Request is uint256;

/// @title ERC7540 Filled Request Structure
/// @notice Holds information about a filled request
/// @dev This struct is used to store the assets and shares of a filled ERC7540 request
struct ERC7540_FilledRequest {
    uint256 assets; // The number of assets involved in the request
    uint256 shares; // The number of shares associated with the request
}

/// @title ERC7540 Library
/// @notice Library for handling ERC7540 requests and conversions
/// @dev This library provides utility functions for converting between assets and shares in ERC7540 requests
library ERC7540Lib {
    /// @notice Converts a given amount of assets to shares, rounding up
    /// @dev Uses full multiplication and division with rounding up
    /// @param self The filled request (ERC7540_FilledRequest) to operate on
    /// @param assets The amount of assets to convert to shares
    /// @return The equivalent amount of shares, rounded up
    function convertToSharesUp(ERC7540_FilledRequest memory self, uint256 assets) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivUp(self.shares, assets, self.assets);
    }

    /// @notice Converts a given amount of assets to shares
    /// @dev Uses full multiplication and division without rounding
    /// @param self The filled request (ERC7540_FilledRequest) to operate on
    /// @param assets The amount of assets to convert to shares
    /// @return The equivalent amount of shares
    function convertToShares(ERC7540_FilledRequest memory self, uint256 assets) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(self.shares, assets, self.assets);
    }

    /// @notice Converts a given amount of shares to assets
    /// @dev Uses full multiplication and division with rounding up
    /// @param self The filled request (ERC7540_FilledRequest) to operate on
    /// @param shares The amount of shares to convert to assets
    /// @return The equivalent amount of assets, rounded up
    function convertToAssets(ERC7540_FilledRequest memory self, uint256 shares) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(self.assets, shares, self.shares);
    }

    /// @notice Converts a given amount of shares to assets, rounding up
    /// @dev Uses full multiplication and division with rounding up
    /// @param self The filled request (ERC7540_FilledRequest) to operate on
    /// @param shares The amount of shares to convert to assets
    /// @return The equivalent amount of assets, rounded up
    function convertToAssetsUp(ERC7540_FilledRequest memory self, uint256 shares) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivUp(self.assets, shares, self.shares);
    }

    /// @notice Adds a value to an ERC7540_Request
    /// @dev Adds a uint256 value to the underlying uint256 of the ERC7540_Request
    /// @param self The ERC7540_Request to operate on
    /// @param x The value to add
    /// @return A new ERC7540_Request with the added value
    function add(ERC7540_Request self, uint256 x) internal pure returns (ERC7540_Request) {
        return ERC7540_Request.wrap(ERC7540_Request.unwrap(self) + x);
    }

    /// @notice Subtracts a value from an ERC7540_Request
    /// @dev Subtracts a uint256 value from the underlying uint256 of the ERC7540_Request
    /// @param self The ERC7540_Request to operate on
    /// @param x The value to subtract
    /// @return A new ERC7540_Request with the subtracted value
    function sub(ERC7540_Request self, uint256 x) internal pure returns (ERC7540_Request) {
        return ERC7540_Request.wrap(ERC7540_Request.unwrap(self) - x);
    }

    function sub0(ERC7540_Request self, uint256 x) internal pure returns (ERC7540_Request) {
        return ERC7540_Request.wrap(x > ERC7540_Request.unwrap(self) ? 0 : ERC7540_Request.unwrap(self) - x);
    }

    /// @notice Unwraps an ERC7540_Request to retrieve the underlying uint256 value
    /// @dev Retrieves the raw uint256 value wrapped by the ERC7540_Request
    /// @param self The ERC7540_Request to unwrap
    /// @return The raw uint256 value of the request
    function unwrap(ERC7540_Request self) internal pure returns (uint256) {
        return ERC7540_Request.unwrap(self);
    }
}
