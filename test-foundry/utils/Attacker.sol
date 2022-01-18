// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";

contract Attacker {
    ILendingPool internal lendingPool;

    constructor(ILendingPool _lendingPool) {
        lendingPool = _lendingPool;
    }

    receive() external payable {}

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        IERC20(_token).approve(_spender, _amount);
    }

    function transfer(
        address _token,
        address _recipient,
        uint256 _amount
    ) external {
        IERC20(_token).transfer(_recipient, _amount);
    }

    function deposit(
        address _asset,
        uint256 _amount,
        address _onBehalfOf,
        uint16 _referralCode
    ) external {
        lendingPool.deposit(_asset, _amount, _onBehalfOf, _referralCode);
    }
}
