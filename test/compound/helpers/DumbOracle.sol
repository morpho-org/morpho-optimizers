// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "src/compound/interfaces/IOracle.sol";

contract DumbOracle is IOracle {
    function consult(uint256 _amountIn) external pure returns (uint256) {
        return _amountIn;
    }
}
