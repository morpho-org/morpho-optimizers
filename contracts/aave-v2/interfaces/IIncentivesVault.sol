// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;
import "./IOracle.sol";

interface IIncentivesVault {
    function isPaused() external view returns (bool);

    function bonus() external view returns (uint256);

    function incentivesTreasuryVault() external view returns (address);

    function oracle() external view returns (IOracle);

    function setOracle(IOracle _newOracle) external;

    function setIncentivesTreasuryVault(address _newIncentivesTreasuryVault) external;

    function setBonus(uint256 _newBonus) external;

    function setPauseStatus(bool _newStatus) external;

    function transferTokensToDao(address _token, uint256 _amount) external;

    function tradeRewardTokensForMorphoTokens(address _to, uint256 _amount) external;
}
