// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";
import "./IRewardsManager.sol";
import "./IMorpho.sol";

interface ILens {
    /// STORAGE ///

    function MAX_BASIS_POINTS() external view returns (uint256);

    function WAD() external view returns (uint256);

    function morpho() external view returns (IMorpho);

    function comptroller() external view returns (IComptroller);

    function rewardsManager() external view returns (IRewardsManager);

    // GENERAL ///

    function getTotalSupply()
        external
        view
        returns (
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount,
            uint256 totalSupplyAmount
        );

    function getTotalBorrow()
        external
        view
        returns (
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount,
            uint256 totalBorrowAmount
        );

    /// MARKETS ///

    function isMarketCreated(address _poolTokenAddress) external view returns (bool);

    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view returns (bool);

    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress)
        external
        view
        returns (bool);

    function getEnteredMarkets(address _user)
        external
        view
        returns (address[] memory enteredMarkets_);

    function getAllMarkets() external view returns (address[] memory marketsCreated_);

    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount
        );

    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            address underlying,
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor,
            uint256 collateralFactor
        );

    function getTotalMarketSupply(address _poolTokenAddress, bool _computeUpdatedIndexes)
        external
        view
        returns (
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount,
            uint256 supplyDeltaAmount
        );

    function getTotalMarketBorrow(address _poolTokenAddress, bool _computeUpdatedIndexes)
        external
        view
        returns (
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount,
            uint256 borrowDeltaAmount
        );

    /// INDEXES ///

    function getCurrentP2PSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getCurrentP2PBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function getIndexes(address _poolTokenAddress, bool _computeUpdatedIndexes)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        );

    /// USERS ///

    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        );

    function getCurrentSupplyBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );

    function getCurrentBorrowBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) external view returns (uint256 debtValue, uint256 maxDebtValue);

    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        bool _computeUpdatedIndexes,
        ICompoundOracle _oracle
    ) external view returns (Types.AssetLiquidityData memory assetData);

    function getUserHealthFactor(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (uint256);

    function isLiquidatable(address _user, address[] memory _updatedMarkets)
        external
        view
        returns (bool);

    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address[] calldata _updatedMarkets
    ) external view returns (uint256 toRepay);

    /// RATES ///

    function getAverageSupplyRatePerBlock(address _poolTokenAddress)
        external
        view
        returns (uint256);

    function getAverageBorrowRatePerBlock(address _poolTokenAddress)
        external
        view
        returns (uint256);

    function getRatesPerBlock(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        );

    function getCurrentUserSupplyRatePerBlock(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getCurrentUserBorrowRatePerBlock(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getNextUserSupplyRatePerBlock(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getNextUserBorrowRatePerBlock(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    /// REWARDS ///

    function getUserUnclaimedRewards(address[] calldata _poolTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards);

    function getAccruedSupplierComp(
        address _supplier,
        address _poolTokenAddress,
        uint256 _balance
    ) external view returns (uint256);

    function getAccruedBorrowerComp(
        address _borrower,
        address _poolTokenAddress,
        uint256 _balance
    ) external view returns (uint256);

    function getCurrentCompSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getCurrentCompBorrowIndex(address _poolTokenAddress) external view returns (uint256);
}
