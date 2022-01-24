// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "contracts/compound/interfaces/dependencies/@openzeppelin/IReentrancyGuard.sol";

interface IPositionsManagerForAaveStorage is IReentrancyGuard {
    function NO_REFERRAL_CODE() external view returns (uint8);

    function VARIABLE_INTEREST_MODE() external view returns (uint8);

    function NMAX() external view returns (uint16);

    function LIQUIDATION_CLOSE_FACTOR_PERCENT() external view returns (uint256);

    function DATA_PROVIDER_ID() external view returns (bytes32);

    function accountMembership(address, address) external view returns (bool);

    function enteredMarkets(address) external view returns (address[] memory);

    function threshold(address) external view returns (uint256);

    function capValue(address) external view returns (uint256);

    function treasuryVault() external view returns (address);
}
