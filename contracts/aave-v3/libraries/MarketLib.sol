// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./Types.sol";

library MarketLib {
    function isCreated(Types.Market storage _market) internal view returns (bool) {
        return _market.underlyingToken != address(0);
    }

    function isCreatedMemory(Types.Market memory _market) internal pure returns (bool) {
        return _market.underlyingToken != address(0);
    }
}
