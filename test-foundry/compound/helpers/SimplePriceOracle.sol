// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {ICToken, ICToken} from "@contracts/compound/interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) public prices;

    function getUnderlyingPrice(address _cToken) public view returns (uint256) {
        return prices[address(ICToken(_cToken).underlying())];
    }

    function setUnderlyingPrice(address _cToken, uint256 _underlyingPriceMantissa) public {
        address asset = address(ICToken(_cToken).underlying());
        prices[asset] = _underlyingPriceMantissa;
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
