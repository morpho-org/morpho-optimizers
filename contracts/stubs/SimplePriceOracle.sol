// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {ICErc20, ICToken} from "../interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) prices;

    function getUnderlyingPrice(ICToken cToken) public view returns (uint256) {
        return prices[address(ICErc20(address(cToken)).underlying())];
    }

    function setUnderlyingPrice(ICToken cToken, uint256 underlyingPriceMantissa) public {
        address asset = address(ICErc20(address(cToken)).underlying());

        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint256 price) public {
        prices[asset] = price;
    }
}
