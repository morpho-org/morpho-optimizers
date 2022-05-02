// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";
import "./IInterestRates.sol";
import "./IRewardsManager.sol";
import "./IPositionsManager.sol";
import "./IIncentivesVault.sol";

import "../libraries/Types.sol";

// prettier-ignore
interface IMorpho {
    
    /// STORAGE ///

    function maxGasForMatching() external view returns (Types.MaxGasForMatching memory);
    function isCompRewardsActive() external view returns (bool);
    function maxSortedUsers() external view returns (uint256);
    function dustThreshold() external view returns (uint256);
    function supplyBalanceInOf(address, address) external view returns (Types.SupplyBalance memory);
    function borrowBalanceInOf(address, address) external view returns (Types.BorrowBalance memory);
    function enteredMarkets(address, uint) external view returns (address);
    function deltas(address) external view returns (Types.Delta memory);
    function marketsCreated() external view returns (address[] memory);
    function marketParameters(address) external view returns (Types.MarketParameters memory);
    function noP2P(address) external view returns (bool);
    function p2pSupplyIndex(address) external view returns (uint256);
    function p2pBorrowIndex(address) external view returns (uint256);
    function lastPoolIndexes(address) external view returns (Types.LastPoolIndexes memory);
    function marketStatuses(address) external view returns (Types.MarketStatuses memory);
    function comptroller() external view returns (IComptroller);
    function interestRates() external view returns (IInterestRates);
    function rewardsManager() external view returns (IRewardsManager);
    function positionsManager() external view returns (IPositionsManager);
    function incentiveVault() external view returns (IIncentivesVault);
    function treasuryVault() external view returns (address);
    function cEth() external view returns (address);
    function wEth() external view returns (address);

    /// GETTERS ///

    function updateP2PIndexes(address _poolTokenAddress) external;
    function getEnteredMarkets(address _user) external view returns (address[] memory enteredMarkets_);
    function getAllMarkets() external view returns (address[] memory marketsCreated_);
    function getHead(address _poolTokenAddress, Types.PositionType _positionType) external view returns (address head);
    function getNext(address _poolTokenAddress, Types.PositionType _positionType, address _user) external view returns (address next);

    /// GOVERNANCE ///

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external;
    function setMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching) external;
    function setTreasuryVault(address _newTreasuryVaultAddress) external;
    function setIncentivesVault(address _newIncentivesVault) external;
    function setRewardsManager(address _rewardsManagerAddress) external;
    function setDustThreshold(uint256 _dustThreshold) external;
    function toggleCompRewardsActivation() external;
    function setNoP2P(address _poolTokenAddress, bool _noP2P) external;
    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor) external;
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor) external;
    function togglePauseStatus(address _poolTokenAddress) external;
    function togglePartialPauseStatus(address _poolTokenAddress) external;
    function claimToTreasury(address _poolTokenAddress, uint256 _amount) external;
    function createMarket(address _poolTokenAddress) external;

    /// USERS ///

    function supply(address _poolTokenAddress, uint256 _amount) external;
    function supply(address _poolTokenAddress, uint256 _amount, uint256 _maxGasToConsume) external;
    function borrow(address _poolTokenAddress, uint256 _amount) external;
    function borrow(address _poolTokenAddress, uint256 _amount, uint256 _maxGasToConsume) external;
    function withdraw(address _poolTokenAddress, uint256 _amount) external;
    function repay(address _poolTokenAddress, uint256 _amount) external;
    function liquidate(address _poolTokenBorrowedAddress, address _poolTokenCollateralAddress, address _borrower, uint256 _amount) external;
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken) external;
}
