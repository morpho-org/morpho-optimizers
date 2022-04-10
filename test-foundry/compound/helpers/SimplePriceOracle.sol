// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ICToken, ICToken} from "@contracts/compound/interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) public prices;

    function getUnderlyingPrice(address _cToken) public view returns (uint256) {
        // Needed for ETH.
        try ICToken(_cToken).underlying() {
            return prices[ICToken(_cToken).underlying()];
        } catch {
            return 1e18;
        }
    }

    function setUnderlyingPrice(address _cToken, uint256 _underlyingPriceMantissa) public {
        // Needed for ETH.
        try ICToken(_cToken).underlying() {
            address asset = ICToken(_cToken).underlying();
            prices[asset] = _underlyingPriceMantissa;
        } catch {
            return;
        }
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
