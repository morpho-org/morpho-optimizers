// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

interface IGetterUnderlyingAsset {
    function UNDERLYING_ASSET_ADDRESS() external returns (address);
}
