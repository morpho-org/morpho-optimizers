// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IGetterUnderlyingAsset {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
