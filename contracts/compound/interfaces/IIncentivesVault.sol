// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./IOracle.sol";

interface IIncentivesVault {
    function setOracle(IOracle _newOracle) external;

    function setMorphoDao(address _newMorphoDao) external;

    function setBonus(uint256 _newBonus) external;

    function setPauseStatus() external;

    function transferMorphoTokensToDao(uint256 _amount) external;

    function tradeCompForMorphoTokens(address _to, uint256 _amount) external;
}
