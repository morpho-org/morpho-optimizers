// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

/// @title Math library.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @dev Implements min helper.
library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
