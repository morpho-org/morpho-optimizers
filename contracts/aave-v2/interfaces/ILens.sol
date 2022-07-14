// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./aave/IPriceOracleGetter.sol";
import "./aave/ILendingPool.sol";
import "./IRewardsManager.sol";
import "./IMorpho.sol";

interface ILens {
    /// STORAGE ///

    function MAX_BASIS_POINTS() external view returns (uint256);

    function WAD() external view returns (uint256);

    function morpho() external view returns (IMorpho);

    function addressesProvider() external view returns (ILendingPoolAddressesProvider);

    function pool() external view returns (ILendingPool);

    /// MARKETS ///

    function isMarketCreated(address _poolTokenAddress) external view returns (bool);

    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view returns (bool);

    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress)
        external
        view
        returns (bool);

    function getAllMarkets() external view returns (address[] memory marketsCreated_);

    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyIndex_,
            uint256 p2pBorrowIndex_,
            uint256 p2pSupplyDelta_,
            uint256 p2pBorrowDelta_,
            uint256 p2pSupplyAmount_,
            uint256 p2pBorrowAmount_
        );

    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            address underlying_,
            bool isCreated_,
            bool p2pDisabled_,
            bool isPaused_,
            bool isPartiallyPaused_,
            uint16 reserveFactor_,
            uint16 p2pIndexCursor_
        );

    /// INDEXES ///

    function getP2PSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getP2PBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function getIndexes(address _poolTokenAddress)
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
        returns (address[] memory enteredMarkets_);

    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        );

    function getUserSupplyBalance(address _user, address _poolTokenAddress)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );

    function getUserBorrowBalance(address _user, address _poolTokenAddress)
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
        IPriceOracleGetter _oracle
    ) external view returns (Types.AssetLiquidityData memory assetData);

    // function isLiquidatable(address _user, address[] memory _updatedMarkets)
    //     external
    //     view
    //     returns (bool);

    // function computeLiquidationRepayAmount(
    //     address _user,
    //     address _poolTokenBorrowedAddress,
    //     address _poolTokenCollateralAddress,
    //     address[] memory _updatedMarkets
    // ) external view returns (uint256 toRepay);

    /// RATES ///

    function getRatesPerYear(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyRate_,
            uint256 p2pBorrowRate_,
            uint256 poolSupplyRate_,
            uint256 poolBorrowRate_
        );

    function getUserSupplyRatePerYear(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getUserBorrowRatePerYear(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getNextUserSupplyRatePerYear(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);

    function getNextUserBorrowRatePerYear(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256);
}
