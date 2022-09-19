// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface ILido {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
