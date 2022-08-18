// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./aave/IPriceOracleGetter.sol";
import "./aave/ILendingPool.sol";
import "./IRewardsManager.sol";
import "./IMorpho.sol";

interface ILens {
    /// STORAGE ///

    function DEFAULT_LIQUIDATION_CLOSE_FACTOR() external view returns (uint16);

    function HEALTH_FACTOR_LIQUIDATION_THRESHOLD() external view returns (uint256);

    function RAY() external view returns (uint256);

    function morpho() external view returns (IMorpho);

    function addressesProvider() external view returns (ILendingPoolAddressesProvider);

    function pool() external view returns (ILendingPool);

    /// GENERAL ///

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

    function isMarketCreated(address _poolToken) external view returns (bool);

    function isMarketCreatedAndNotPaused(address _poolToken) external view returns (bool);

    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolToken)
        external
        view
        returns (bool);

    function getAllMarkets() external view returns (address[] memory marketsCreated_);

    function getMainMarketData(address _poolToken)
        external
        view
        returns (
            uint256 avgSupplyRatePerYear,
            uint256 avgBorrowRatePerYear,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        );

    function getAdvancedMarketData(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex,
            uint32 lastUpdateTimestamp,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta
        );

    function getMarketConfiguration(address _poolToken)
        external
        view
        returns (
            address underlying,
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor
        );

    function getTotalMarketSupply(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount,
            uint256 supplyDeltaAmount
        );

    function getTotalMarketBorrow(address _poolToken)
        external
        view
        returns (
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount,
            uint256 borrowDeltaAmount
        );

    /// INDEXES ///

    function getCurrentP2PSupplyIndex(address _poolToken) external view returns (uint256);

    function getCurrentP2PBorrowIndex(address _poolToken) external view returns (uint256);

    function getIndexes(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        );

    /// USERS ///

    function getEnteredMarkets(address _user)
        external
        view
        returns (address[] memory enteredMarkets);

    function getUserHealthFactor(address _user) external view returns (uint256 healthFactor);

    function getUserBalanceStates(address _user)
        external
        view
        returns (Types.LiquidityData memory assetData);

    function getCurrentSupplyBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );

    function getCurrentBorrowBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );

    function getUserMaxCapacitiesForAsset(address _user, address _poolToken)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) external view returns (Types.LiquidityData memory assetData);

    function getUserHypotheticalHealthFactor(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) external view returns (uint256 healthFactor);

    function getUserLiquidityDataForAsset(
        address _user,
        address _poolToken,
        IPriceOracleGetter _oracle
    ) external view returns (Types.AssetLiquidityData memory assetData);

    function isLiquidatable(address _user) external view returns (bool);

    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress
    ) external view returns (uint256 toRepay);

    /// RATES ///

    function getAverageSupplyRatePerBlock(address _poolToken) external view returns (uint256);

    function getAverageBorrowRatePerBlock(address _poolToken) external view returns (uint256);

    function getRatesPerYear(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        );

    function getCurrentUserSupplyRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256);

    function getCurrentUserBorrowRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256);

    function getNextUserSupplyRatePerYear(address _poolToken, address _user)
        external
        view
        returns (uint256);

    function getNextUserBorrowRatePerYear(address _poolToken, address _user)
        external
        view
        returns (uint256);
}
