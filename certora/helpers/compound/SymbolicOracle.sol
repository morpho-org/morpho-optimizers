// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ICompoundOracle} from "../munged/compound/interfaces/compound/ICompound.sol";

contract SymbolicOracle is ICompoundOracle {
    mapping(address => uint256) public underlyingPrice;
    mapping(address => mapping(address => uint256)) public unclaimedRewards;

    function getUnderlyingPrice(address _token) external view override returns (uint256) {
        return underlyingPrice[_token];
    }

    function setUnderlyingPrice(address _token, uint256 _price) public {
        underlyingPrice[_token] = _price;
    }

    function accrueUserUnclaimedRewards(address[] calldata _assets, address _user)
        external
        view
        returns (uint256 unclaimedRewards_)
    {
        unclaimedRewards_ = unclaimedRewards[_assets[0]][_user];
    }
}
