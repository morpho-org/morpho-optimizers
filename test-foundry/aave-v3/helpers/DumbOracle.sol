// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v3/interfaces/IOracle.sol";

contract DumbOracle is IOracle {
    function consult(uint256 _amountIn) external pure returns (uint256) {
        return _amountIn;
    }
}
