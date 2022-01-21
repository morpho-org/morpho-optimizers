// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";
import "./IPositionsManagerForAave.sol";

interface IMarketsManagerForAave {
    // inherited from Ownable
    function owner() external returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function isCreated(address) external view returns (bool);

    function borrowP2PSPY(address) external view returns (uint256);

    function exchangeRatesLastUpdateTimestamp(address) external view returns (uint256);

    function setPositionsManager(address _positionsManagerForAave) external;

    function noP2P(address _marketAddress) external view returns (bool);

    function supplyP2PSPY(address _marketAddress) external returns (uint256);

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external;

    function setReserveFactor(uint256 _newReserveFactor) external;

    function supplyP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function borrowP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function updateCapValue(address _marketAddress, uint256 _newCapValue) external;

    function updateRates(address _marketAddress) external;
}
