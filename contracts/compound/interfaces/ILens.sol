// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";
import "./IMorpho.sol";

interface ILens {
    function MAX_BASIS_POINTS() external view returns (uint256);

    function WAD() external view returns (uint256);

    function morpho() external view returns (IMorpho);

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
            uint256 p2pSupplyIndex_,
            uint256 p2pBorrowIndex_,
            uint32 lastUpdateBlockNumber_,
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
            uint256 reserveFactor_,
            uint256 collateralFactor_
        );

    function getRates(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyRate_,
            uint256 p2pBorrowRate_,
            uint256 poolSupplyRate_,
            uint256 poolBorrowRate_
        );

    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        );

    function getUpdatedUserSupplyBalance(address _user, address _poolTokenAddress)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );

    function getUpdatedUserBorrowBalance(address _user, address _poolTokenAddress)
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

    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function getIndexes(address _poolTokenAddress, bool _computeUpdatedIndexes)
        external
        view
        returns (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        );

    function isLiquidatable(address _user, address[] memory _updatedMarkets)
        external
        view
        returns (bool);

    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address[] memory _updatedMarkets
    ) external view returns (uint256 toRepay);
}
