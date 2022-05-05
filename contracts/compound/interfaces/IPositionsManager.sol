// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IPositionsManager {
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external;

    function repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external returns (uint256);
}
