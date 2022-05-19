// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

/// @title Math library.
/// @dev Implements min helpers.
library Math {
    function min(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return a < b ? a < c ? a : c : b < c ? b : c;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
