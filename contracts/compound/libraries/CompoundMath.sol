// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

/// @title CompoundMath.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @dev Library emulating in solidity 8+ the behavior of Compound's mulScalarTruncate and divScalarByExpTruncate functions.
library CompoundMath {
    /// ERRORS ///

    /// @notice Reverts when the number exceeds 224 bits.
    error NumberExceeds224Bits();

    /// @notice Reverts when the number exceeds 32 bits.
    error NumberExceeds32Bits();

    /// INTERNAL ///

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / 1e18;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        return ((1e18 * x * 1e18) / y) / 1e18;
    }

    function safe224(uint256 n) internal pure returns (uint224) {
        if (n >= 2**224) revert NumberExceeds224Bits();
        return uint224(n);
    }

    function safe32(uint256 n) internal pure returns (uint32) {
        if (n >= 2**32) revert NumberExceeds32Bits();
        return uint32(n);
    }

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

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : 0;
    }
}
