// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) public prices;

    function getAssetPrice(address _underlying) public view returns (uint256) {
        return prices[_underlying];
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
