// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

interface IEntryPositionsManager {
    function supplyLogic(
        address _poolToken,
        address _supplier,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 supplied);

    function borrowLogic(
        address _poolToken,
        uint256 _amount,
        address _receiver,
        uint256 _maxGasForMatching
    ) external returns (uint256 borrowed);
}
