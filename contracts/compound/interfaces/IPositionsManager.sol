// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IPositionsManager {
    function supplyLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function borrowLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function withdrawLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function repayLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function liquidateLogic(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external;
}
