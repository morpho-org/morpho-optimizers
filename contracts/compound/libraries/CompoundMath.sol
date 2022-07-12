// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

/// @title CompoundMath.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @dev Library emulating in solidity 8+ the behavior of Compound's mulScalarTruncate and divScalarByExpTruncate functions.
library CompoundMath {
    uint256 public constant WAD = 1e18;
    uint256 public constant SCALE = 1e36;

    /// ERRORS ///

    /// @notice Reverts when the number exceeds 224 bits.
    error NumberExceeds224Bits();

    /// @notice Reverts when the number exceeds 32 bits.
    error NumberExceeds32Bits();

    /// INTERNAL ///

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := div(mul(x, y), WAD)
        }
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := div(div(mul(x, SCALE), WAD), y)
        }
    }

    function safe224(uint256 n) internal pure returns (uint224) {
        if (n >= 2**224) revert NumberExceeds224Bits();
        return uint224(n);
    }

    function safe32(uint256 n) internal pure returns (uint32) {
        if (n >= 2**32) revert NumberExceeds32Bits();
        return uint32(n);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function safeSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            if gt(x, y) {
                z := sub(x, y)
            }
        }
    }
}
