// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IOracle {
    function consult(uint256 _amountIn) external returns (uint256);
}
