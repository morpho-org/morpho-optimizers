// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

interface IOracle {
    function consult(uint256 _amountIn, address _tokenIn) external returns (uint256);
}
