// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";
import "./IInterestRates.sol";
import "./IRewardsManager.sol";
import "./IPositionsManager.sol";
import "./IIncentivesVault.sol";

enum PositionType {
    SUPPLIERS_IN_P2P,
    SUPPLIERS_ON_POOL,
    BORROWERS_IN_P2P,
    BORROWERS_ON_POOL
}

struct SupplyBalance {
    uint256 inP2P;
    uint256 onPool;
}

struct BorrowBalance {
    uint256 inP2P;
    uint256 onPool;
}

struct MaxGasForMatching {
    uint64 supply;
    uint64 borrow;
    uint64 withdraw;
    uint64 repay;
}

struct AssetLiquidityData {
    uint256 collateralValue;
    uint256 maxDebtValue;
    uint256 debtValue;
    uint256 underlyingPrice;
    uint256 collateralFactor;
}

struct LiquidityData {
    uint256 collateralValue;
    uint256 maxDebtValue;
    uint256 debtValue;
}

struct LastPoolIndexes {
    uint32 lastUpdateBlockNumber;
    uint112 lastSupplyPoolIndex;
    uint112 lastBorrowPoolIndex;
}

struct MarketParameters {
    uint16 reserveFactor;
    uint16 p2pIndexCursor;
}

struct MarketStatuses {
    bool isCreated;
    bool isPaused;
    bool isPartiallyPaused;
}

struct Delta {
    uint256 supplyP2PDelta;
    uint256 borrowP2PDelta;
    uint256 supplyP2PAmount;
    uint256 borrowP2PAmount;
}

// prettier-ignore
interface IMorpho {
    
    /// STORAGE ///

    function maxGasForMatching() external view returns (MaxGasForMatching memory);
    function isCompRewardsActive() external view returns (bool);
    function maxSortedUsers() external view returns (uint256);
    function dustThreshold() external view returns (uint256);
    function supplyBalanceInOf(address, address) external view returns (SupplyBalance memory);
    function borrowBalanceInOf(address, address) external view returns (BorrowBalance memory);
    function enteredMarkets(address, uint) external view returns (address);
    function deltas(address) external view returns (Delta memory);
    function marketsCreated() external view returns (address[] memory);
    function marketParameters(address) external view returns (MarketParameters memory);
    function noP2P(address) external view returns (bool);
    function p2pSupplyIndex(address) external view returns (uint256);
    function p2pBorrowIndex(address) external view returns (uint256);
    function lastPoolIndexes(address) external view returns (LastPoolIndexes memory);
    function marketStatuses(address) external view returns (MarketStatuses memory);
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
    function getHead(address _poolTokenAddress, PositionType _positionType) external view returns (address head);
    function getNext(address _poolTokenAddress, PositionType _positionType, address _user) external view returns (address next);

    /// GOVERNANCE ///

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external;
    function setMaxGasForMatching(MaxGasForMatching memory _maxGasForMatching) external;
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
