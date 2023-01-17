// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

contract SymbolicOracle {
    mapping(address => uint256) public underlyingPrice;
    mapping(address => mapping(address => uint256)) public unclaimedRewards;

    function getUnderlyingPrice(address _token) external view returns (uint256) {
        return underlyingPrice[_token];
    }

    // this function is specifically for usage in the spec, you can also directly assign prices to the underlyingPrice mapping
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
