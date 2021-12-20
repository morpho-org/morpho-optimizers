// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";

contract User {
    PositionsManagerForAave internal positionsManager;
    MarketsManagerForAave internal marketsManager;

    constructor(PositionsManagerForAave _positionsManager, MarketsManagerForAave _marketsManager) {
        positionsManager = _positionsManager;
        marketsManager = _marketsManager;
    }

    receive() external payable {}

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        IERC20(_token).approve(_spender, _amount);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.supply(_poolTokenAddress, _amount);
    }
}
