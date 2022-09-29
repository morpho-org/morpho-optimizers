// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

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
        address _receiver,
        uint256 _maxGasForMatching
    ) external;

    function withdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external returns (uint256 withdrawn);

    function repayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 repaid);

    function liquidateLogic(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        address _receiver,
        uint256 _amount
    ) external returns (uint256 seized);

    function increaseP2PDeltasLogic(address _poolToken, uint256 _amount) external;
}
