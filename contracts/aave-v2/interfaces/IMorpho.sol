// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";
import "./IEntryPositionsManager.sol";
import "./IExitPositionsManager.sol";
import "./IInterestRatesManager.sol";
import "./IIncentivesVault.sol";
import "./IRewardsManager.sol";

import "../libraries/Types.sol";

// prettier-ignore
interface IMorpho {

    /// STORAGE ///

    function NO_REFERRAL_CODE() external view returns(uint8);
    function VARIABLE_INTEREST_MODE() external view returns(uint8);
    function MAX_BASIS_POINTS() external view returns(uint16);
    function MAX_CLAIMABLE_RESERVE() external view returns(uint16);
    function DEFAULT_LIQUIDATION_CLOSE_FACTOR() external view returns(uint16);
    function HEALTH_FACTOR_LIQUIDATION_THRESHOLD() external view returns(uint256);
    function BORROWING_MASK() external view returns(uint256);
    function MAX_NB_OF_MARKETS() external view returns(uint256);

    function isClaimRewardsPaused() external view returns (bool);
    function defaultMaxGasForMatching() external view returns (Types.MaxGasForMatching memory);
    function maxSortedUsers() external view returns (uint256);
    function supplyBalanceInOf(address, address) external view returns (Types.SupplyBalance memory);
    function borrowBalanceInOf(address, address) external view returns (Types.BorrowBalance memory);
    function deltas(address) external view returns (Types.Delta memory);
    function marketParameters(address) external view returns (Types.MarketParameters memory);
    function p2pDisabled(address) external view returns (bool);
    function p2pSupplyIndex(address) external view returns (uint256);
    function p2pBorrowIndex(address) external view returns (uint256);
    function poolIndexes(address) external view returns (Types.PoolIndexes memory);
    function marketStatus(address) external view returns (Types.MarketStatus memory);
    function interestRatesManager() external view returns (IInterestRatesManager);
    function rewardsManager() external view returns (IRewardsManager);
    function entryPositionsManager() external view returns (IEntryPositionsManager);
    function exitPositionsManager() external view returns (IExitPositionsManager);
    function aaveIncentivesController() external view returns (IAaveIncentivesController);
    function addressesProvider() external view returns (ILendingPoolAddressesProvider);
    function incentivesVault() external view returns (IIncentivesVault);
    function pool() external view returns (ILendingPool);
    function treasuryVault() external view returns (address);
    function borrowMask(address) external view returns (bytes32);
    function userMarkets(address) external view returns (bytes32);

    /// UTILS ///

    function updateIndexes(address _poolTokenAddress) external;

    /// GETTERS ///

    function getMarketsCreated() external view returns (address[] memory marketsCreated_);
    function liquidityData(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount) external view returns (Types.LiquidityData memory);
    function getHead(address _poolTokenAddress, Types.PositionType _positionType) external view returns (address head);
    function getNext(address _poolTokenAddress, Types.PositionType _positionType, address _user) external view returns (address next);

    /// GOVERNANCE ///

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external;
    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching) external;
    function setTreasuryVault(address _newTreasuryVaultAddress) external;
    function setIncentivesVault(address _newIncentivesVault) external;
    function setRewardsManager(address _rewardsManagerAddress) external;
    function setP2PDisabled(address _poolTokenAddress, bool _p2pDisabled) external;
    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor) external;
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor) external;
    function setPauseStatusForAllMarkets(bool _newStatus) external;
    function setClaimRewardsPauseStatus(bool _newStatus) external;
    function setPauseStatus(address _poolTokenAddress, bool _newStatus) external;
    function setPartialPauseStatus(address _poolTokenAddress, bool _newStatus) external;
    function setExitPositionsManager(IExitPositionsManager _exitPositionsManager) external;
    function setEntryPositionsManager(IEntryPositionsManager _entryPositionsManager) external;
    function setInterestRatesManager(IInterestRatesManager _interestRatesManager) external;
    function claimToTreasury(address[] calldata _poolTokenAddresses) external;
    function createMarket(address _poolTokenAddress, Types.MarketParameters calldata _marketParams) external;

    /// USERS ///

    function supply(address _poolTokenAddress, address _onBehalf, uint256 _amount) external;
    function supply(address _poolTokenAddress, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) external;
    function borrow(address _poolTokenAddress, uint256 _amount) external;
    function borrow(address _poolTokenAddress, uint256 _amount, uint256 _maxGasForMatching) external;
    function withdraw(address _poolTokenAddress, uint256 _amount) external;
    function repay(address _poolTokenAddress, address _onBehalf, uint256 _amount) external;
    function liquidate(address _poolTokenBorrowedAddress, address _poolTokenCollateralAddress, address _borrower, uint256 _amount) external;
    function claimRewards(address[] calldata _cTokenAddresses, bool _tradeForMorphoToken) external returns (uint256 claimedAmount);
}
