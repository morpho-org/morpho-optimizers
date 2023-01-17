// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IPositionsManager {
    function supplyLogic(
        address _poolToken,
        address _supplier,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function borrowLogic(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function withdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external;

    function repayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function liquidateLogic(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external;

    function increaseP2PDeltasLogic(address _poolToken, uint256 _amount) external;
}
