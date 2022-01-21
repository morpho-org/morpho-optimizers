// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/IProtocolDataProvider.sol";
import "./aave/ILendingPool.sol";
import "./IMarketsManagerForAave.sol";
import "./IMatchingEngineManager.sol";

interface IPositionsManagerForAaveStorage {
    function accountMembership(address, address) external view returns (bool);

    function enteredMarkets(address) external view returns (address[] memory);

    function threshold(address) external view returns (uint256);

    function capValue(address) external view returns (uint256);
}
