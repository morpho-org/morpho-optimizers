// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/IAaveIncentivesController.sol";
import "./aave/IProtocolDataProvider.sol";
import "./aave/ILendingPool.sol";
import "./IMarketsManagerForAave.sol";
import "./IMatchingEngineManager.sol";
import "./IRewardsManager.sol";
import "./dependencies/@openzeppelin/IReentrancyGuard.sol";

interface IPositionsManagerForAaveStorage is IReentrancyGuard {
    struct SupplyBalance {
        uint256 inP2P;
        uint256 onPool;
    }

    struct BorrowBalance {
        uint256 inP2P;
        uint256 onPool;
    }

    function MAX_BASIS_POINTS() external view returns (uint256);

    function NMAX() external view returns (uint16);

    function NO_REFERRAL_CODE() external view returns (uint8);

    function VARIABLE_INTEREST_MODE() external view returns (uint8);

    function LIQUIDATION_CLOSE_FACTOR_PERCENT() external view returns (uint256);

    function DATA_PROVIDER_ID() external view returns (bytes32);

    function supplyBalanceInOf(address, address) external view returns (SupplyBalance memory);

    function borrowBalanceInOf(address, address) external view returns (BorrowBalance memory);

    function accountMembership(address, address) external view returns (bool);

    function enteredMarkets(address) external view returns (address[] memory);

    function threshold(address) external view returns (uint256);

    function capValue(address) external view returns (uint256);

    function marketsManagerForAave() external view returns (IMarketsManagerForAave);

    function aaveIncentivesController() external view returns (IAaveIncentivesController);

    function rewardsManager() external view returns (IRewardsManager);

    function addressesProvider() external view returns (ILendingPoolAddressesProvider);

    function lendingPool() external view returns (ILendingPool);

    function dataProvider() external view returns (IProtocolDataProvider);

    function matchingEngineManager() external view returns (IMatchingEngineManager);

    function treasuryVault() external view returns (address);
}
