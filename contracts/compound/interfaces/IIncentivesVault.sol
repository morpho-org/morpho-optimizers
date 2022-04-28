// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IIncentivesVault {
    function switchCompToMorphoTokens(address _to, uint256 _amount) external;
}
