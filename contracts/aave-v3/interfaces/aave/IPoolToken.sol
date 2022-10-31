// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

interface IPoolToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
