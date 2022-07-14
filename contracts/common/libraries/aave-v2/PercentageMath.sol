// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {Errors} from "./Errors.sol";

/// @title PercentageMath.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Library to conduct percentage multiplication inspired by https://github.com/aave/protocol-v2/blob/master/contracts/protocol/libraries/math/PercentageMath.sol.
library PercentageMath {
    uint256 internal constant PERCENTAGE_FACTOR = 1e4; // Percentage plus two decimals.
    uint256 internal constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    /// @dev Executes a percentage multiplication.
    /// @param value The value of which the percentage needs to be calculated.
    /// @param percentage The percentage of the value to be calculated.
    /// @return The percentage of value.
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        unchecked {
            if (value == 0 || percentage == 0) return 0;

            require(
                value <= (type(uint256).max - HALF_PERCENT) / percentage,
                Errors.MATH_MULTIPLICATION_OVERFLOW
            );

            return (value * percentage + HALF_PERCENT) / PERCENTAGE_FACTOR;
        }
    }

    /// @dev Executes a percentage division.
    /// @param value The value of which the percentage needs to be calculated.
    /// @param percentage The percentage of the value to be calculated.
    /// @return The value divided the percentage.
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        unchecked {
            require(percentage != 0, Errors.MATH_DIVISION_BY_ZERO);
            uint256 halfPercentage = percentage / 2;

            require(
                value <= (type(uint256).max - halfPercentage) / PERCENTAGE_FACTOR,
                Errors.MATH_MULTIPLICATION_OVERFLOW
            );

            return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
        }
    }
}
