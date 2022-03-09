// SPDX-License-Identifier: BSD-2-Clause
pragma solidity 0.8.10;

/// @title CompoundMath
/// @dev library emulating in solidity 8+ the behavior of Compound's mulScalarTruncate and divScalarByExpTruncate functions.
library CompoundMath {
    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / 1e18;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        return ((1e18 * x * 1e18) / y) / 1e18;
    }
}
