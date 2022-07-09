// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@contracts/aave-v3/interfaces/IOracle.sol";

contract DumbOracle is IOracle {
    function consult(uint256 _amountIn, address _tokenIn) external pure returns (uint256) {
        return _amountIn;
    }
}
