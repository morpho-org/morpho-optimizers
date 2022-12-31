// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import "./IInterestRatesManager.sol";
import "./IPositionsManager.sol";
import "./IRewardsManager.sol";

import "../libraries/Types.sol";

// prettier-ignore
interface IMorpho {

    /// STORAGE ///

    function CTOKEN_DECIMALS() external view returns (uint8);
    function MAX_BASIS_POINTS() external view returns (uint16);
    function WAD() external view returns (uint256);
    function isClaimRewardsPaused() external view returns (bool);
    function defaultMaxGasForMatching() external view returns (Types.MaxGasForMatching memory);
    function maxSortedUsers() external view returns (uint256);
    function dustThreshold() external view returns (uint256);
    function supplyBalanceInOf(address, address) external view returns (Types.SupplyBalance memory);
    function borrowBalanceInOf(address, address) external view returns (Types.BorrowBalance memory);
    function enteredMarkets(address, uint256) external view returns (address);
    function deltas(address) external view returns (Types.Delta memory);
    function marketParameters(address) external view returns (Types.MarketParameters memory);
    function marketPauseStatus(address) external view returns (Types.MarketPauseStatus memory);
    function p2pDisabled(address) external view returns (bool);
    function p2pSupplyIndex(address) external view returns (uint256);
    function p2pBorrowIndex(address) external view returns (uint256);
    function lastPoolIndexes(address) external view returns (Types.LastPoolIndexes memory);
    function marketStatus(address) external view returns (Types.MarketStatus memory);
    function comptroller() external view returns (IComptroller);
    function interestRatesManager() external view returns (IInterestRatesManager);
    function rewardsManager() external view returns (IRewardsManager);
    function positionsManager() external view returns (IPositionsManager);
    function incentivesVault() external view returns (address);
    function treasuryVault() external view returns (address);
    function cEth() external view returns (address);
    function wEth() external view returns (address);

    /// GETTERS ///

    function getEnteredMarkets(address _user) external view returns (address[] memory);
    function getAllMarkets() external view returns (address[] memory);
    function getHead(address _poolToken, Types.PositionType _positionType) external view returns (address head);
    function getNext(address _poolToken, Types.PositionType _positionType, address _user) external view returns (address next);

    /// GOVERNANCE ///

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external;
    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching) external;
    function setRewardsManager(address _rewardsManagerAddress) external;
    function setPositionsManager(IPositionsManager _positionsManager) external;
    function setInterestRatesManager(IInterestRatesManager _interestRatesManager) external;
    function setTreasuryVault(address _treasuryVault) external;
    function setDustThreshold(uint256 _dustThreshold) external;
    function setIsP2PDisabled(address _poolToken, bool _isP2PDisabled) external;
    function setReserveFactor(address _poolToken, uint256 _newReserveFactor) external;
    function setP2PIndexCursor(address _poolToken, uint16 _p2pIndexCursor) external;
    function setIsPausedForAllMarkets(bool _isPaused) external;
    function setIsClaimRewardsPaused(bool _isPaused) external;
    function setIsSupplyPaused(address _poolToken, bool _isPaused) external;
    function setIsBorrowPaused(address _poolToken, bool _isPaused) external;
    function setIsWithdrawPaused(address _poolToken, bool _isPaused) external;
    function setIsRepayPaused(address _poolToken, bool _isPaused) external;
    function setIsLiquidateCollateralPaused(address _poolToken, bool _isPaused) external;
    function setIsLiquidateBorrowPaused(address _poolToken, bool _isPaused) external;
    function claimToTreasury(address[] calldata _poolTokens, uint256[] calldata _amounts) external;
    function createMarket(address _poolToken, Types.MarketParameters calldata _params) external;

    /// USERS ///

    function supply(address _poolToken, uint256 _amount) external;
    function supply(address _poolToken, address _onBehalf, uint256 _amount) external;
    function supply(address _poolToken, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) external;
    function borrow(address _poolToken, uint256 _amount) external;
    function borrow(address _poolToken, uint256 _amount, uint256 _maxGasForMatching) external;
    function withdraw(address _poolToken, uint256 _amount) external;
    function withdraw(address _poolToken, uint256 _amount, address _receiver) external;
    function repay(address _poolToken, uint256 _amount) external;
    function repay(address _poolToken, address _onBehalf, uint256 _amount) external;
    function liquidate(address _poolTokenBorrowed, address _poolTokenCollateral, address _borrower, uint256 _amount) external;
    function claimRewards(address[] calldata _cTokenAddresses, bool _tradeForMorphoToken) external returns (uint256 claimedAmount);
}
