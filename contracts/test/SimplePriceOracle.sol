// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {ICErc20, ICToken} from "../interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) public prices;

    function getUnderlyingPrice(ICToken _cToken) public view returns (uint256) {
        return prices[address(ICErc20(address(_cToken)).underlying())];
    }

    function setUnderlyingPrice(ICToken _cToken, uint256 _underlyingPriceMantissa) public {
        address asset = address(ICErc20(address(_cToken)).underlying());
        prices[asset] = _underlyingPriceMantissa;
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
