// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

/// @title Math library.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @dev Implements min helpers.
library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Returns max(a-b, 0).
    function zeroFloorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : 0;
        }
    }
}
