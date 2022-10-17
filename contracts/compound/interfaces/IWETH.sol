// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}
