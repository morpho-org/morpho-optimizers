// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/aave-v2/interfaces/IOracle.sol";

contract DumbOracle is IOracle {
    function consult(uint256 _amountIn) external pure returns (uint256) {
        return _amountIn;
    }
}
