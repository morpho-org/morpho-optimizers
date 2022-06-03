// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/IAToken.sol";
import "./interfaces/IMorpho.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho/data-structures/contracts/HeapOrdering.sol";
import "./libraries/aave/PercentageMath.sol";
import "./libraries/aave/WadRayMath.sol";
import "./libraries/Math.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice User accessible getters.
contract Lens {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    /// STRUCTS ///

    struct Params {
        uint256 lastP2PSupplyIndex; // The peer-to-peer supply index at last update.
        uint256 lastP2PBorrowIndex; // The peer-to-peer borrow index at last update.
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 lastPoolSupplyIndex; // The pool supply index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }

    /// STORAGE ///

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.
    uint256 public constant RAY = 1e27;
    IMorpho public immutable morpho;
    ILendingPoolAddressesProvider public immutable addressesProvider;
    ILendingPool public immutable lendingPool;

    /// CONSTRUCTOR ///

    constructor(address _morphoAddress, ILendingPoolAddressesProvider _addressesProvider) {
        morpho = IMorpho(_morphoAddress);
        addressesProvider = _addressesProvider;
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
    }

    /// ERRORS ///

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// GETTERS ///

    /// @notice Checks if a market is created.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreated(address _poolTokenAddress) external view returns (bool) {
        return morpho.marketStatus(_poolTokenAddress).isCreated;
    }

    /// @notice Checks if a market is created and not paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view returns (bool) {
        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        return marketStatus.isCreated && !marketStatus.isPaused;
    }

    /// @notice Checks if a market is created and not paused or partially paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created, not paused and not partially paused, otherwise false.
    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress)
        external
        view
        returns (bool)
    {
        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        return marketStatus.isCreated && !marketStatus.isPaused && !marketStatus.isPartiallyPaused;
    }

    /// @notice Returns the current balance state of the user.
    /// @param _user The user to determine liquidity for.
    /// @return liquidityData The liquidity data of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (Types.LiquidityData memory liquidityData)
    {
        return getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        Types.LiquidityData memory data;
        Types.AssetLiquidityData memory assetData;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 numberOfEnteredMarkets = enteredMarkets.length;

        for (uint256 i; i < numberOfEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                data.collateralValue += assetData.collateralValue;
                data.debtValue += assetData.debtValue;
                data.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
                data.liquidationThresholdValue += assetData.collateralValue.percentMul(
                    assetData.liquidationThreshold
                );
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.collateralValue += assetData.collateralValue;
        data.debtValue += assetData.debtValue;
        data.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
        data.liquidationThresholdValue += assetData.collateralValue.percentMul(
            assetData.liquidationThreshold
        );

        data.healthFactor = data.debtValue == 0
            ? type(uint256).max
            : data.liquidationThresholdValue.wadDiv(data.debtValue);

        // Not possible to withdraw nor borrow.
        if (data.healthFactor <= HEALTH_FACTOR_LIQUIDATION_THRESHOLD) return (0, 0);

        if (data.debtValue == 0)
            withdrawable =
                (assetData.collateralValue * assetData.tokenUnit) /
                assetData.underlyingPrice;
        else
            withdrawable =
                ((data.liquidationThresholdValue - data.debtValue) * assetData.tokenUnit) /
                assetData.underlyingPrice;

        borrowable =
            ((data.maxLoanToValue - data.debtValue) * assetData.tokenUnit) /
            assetData.underlyingPrice;
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the aToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        IPriceOracleGetter _oracle
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();

        assetData.underlyingPrice = _oracle.getAssetPrice(underlyingAddress); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = lendingPool
        .getConfiguration(underlyingAddress)
        .getParamsMemory();

        assetData.tokenUnit = 10**assetData.reserveDecimals;
        assetData.debtValue =
            (_getUserBorrowBalanceInOf(_poolTokenAddress, _user) * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.collateralValue =
            (_getUserSupplyBalanceInOf(_poolTokenAddress, _user) * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return liquidityData The liquidity data of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (Types.LiquidityData memory liquidityData) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 numberOfEnteredMarkets = enteredMarkets.length;

        for (uint256 i; i < numberOfEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            liquidityData.collateralValue += assetData.collateralValue;
            liquidityData.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
            liquidityData.liquidationThresholdValue += assetData.collateralValue.percentMul(
                assetData.liquidationThreshold
            );
            liquidityData.debtValue += assetData.debtValue;

            if (_poolTokenAddress == poolTokenEntered) {
                if (_borrowedAmount > 0)
                    liquidityData.debtValue +=
                        (_borrowedAmount * assetData.underlyingPrice) /
                        assetData.tokenUnit;

                if (_withdrawnAmount > 0) {
                    liquidityData.collateralValue -=
                        (_withdrawnAmount * assetData.underlyingPrice) /
                        assetData.tokenUnit;
                    liquidityData.maxLoanToValue -= ((_withdrawnAmount *
                        assetData.underlyingPrice) / assetData.tokenUnit)
                    .percentMul(assetData.ltv);
                    liquidityData.liquidationThresholdValue -= ((_withdrawnAmount *
                        assetData.underlyingPrice) / assetData.tokenUnit)
                    .percentMul(assetData.liquidationThreshold);
                }
            }

            unchecked {
                ++i;
            }
        }

        liquidityData.healthFactor = liquidityData.debtValue == 0
            ? type(uint256).max
            : liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue);
    }

    /// @notice Returns the updated peer-to-peer indexes.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    /// @return newP2PBorrowIndex The peer-to-peer supply index after update.
    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        if (block.timestamp == morpho.poolIndexes(_poolTokenAddress).lastUpdateTimestamp) {
            newP2PSupplyIndex = morpho.p2pSupplyIndex(_poolTokenAddress);
            newP2PBorrowIndex = morpho.p2pBorrowIndex(_poolTokenAddress);
        } else {
            Types.PoolIndexes memory poolIndexes = morpho.poolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 poolSupplyIndex, uint256 poolBorrowIndex) = _computeCompoundsIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            (newP2PSupplyIndex, newP2PBorrowIndex) = _computeP2PIndexes(params);
        }
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.timestamp == morpho.poolIndexes(_poolTokenAddress).lastUpdateTimestamp)
            return morpho.p2pSupplyIndex(_poolTokenAddress);
        else {
            Types.PoolIndexes memory poolIndexes = morpho.poolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 poolSupplyIndex, uint256 poolBorrowIndex) = _computeCompoundsIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            return _computeP2PSupplyIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer borrow index after update.
    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.timestamp == morpho.poolIndexes(_poolTokenAddress).lastUpdateTimestamp)
            return morpho.p2pBorrowIndex(_poolTokenAddress);
        else {
            Types.PoolIndexes memory poolIndexes = morpho.poolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 poolSupplyIndex, uint256 poolBorrowIndex) = _computeCompoundsIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            return _computeP2PBorrowIndex(params);
        }
    }

    /// @notice Returns market's data.
    /// @return p2pSupplyIndex_ The peer-to-peer supply index of the market.
    /// @return p2pBorrowIndex_ The peer-to-peer borrow index of the market.
    /// @return lastUpdateTimestamp_ The last timestamp when peer-to-peer indexes where updated.
    /// @return p2pSupplyDelta_ The peer-to-peer supply delta (in scaled balance).
    /// @return p2pBorrowDelta_ The peer-to-peer borrow delta (in adUnit).
    /// @return p2pSupplyAmount_ The peer-to-peer supply amount (in peer-to-peer unit).
    /// @return p2pBorrowAmount_ The peer-to-peer borrow amount (in peer-to-peer unit).
    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyIndex_,
            uint256 p2pBorrowIndex_,
            uint32 lastUpdateTimestamp_,
            uint256 p2pSupplyDelta_,
            uint256 p2pBorrowDelta_,
            uint256 p2pSupplyAmount_,
            uint256 p2pBorrowAmount_
        )
    {
        {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            p2pSupplyDelta_ = delta.p2pSupplyDelta;
            p2pBorrowDelta_ = delta.p2pBorrowDelta;
            p2pSupplyAmount_ = delta.p2pSupplyAmount;
            p2pBorrowAmount_ = delta.p2pBorrowAmount;
        }
        p2pSupplyIndex_ = morpho.p2pSupplyIndex(_poolTokenAddress);
        p2pBorrowIndex_ = morpho.p2pBorrowIndex(_poolTokenAddress);
        lastUpdateTimestamp_ = morpho.poolIndexes(_poolTokenAddress).lastUpdateTimestamp;
    }

    /// @notice Returns market's configuration.
    /// @return isCreated_ Whether the market is created or not.
    /// @return p2pDisabled_ Whether user are put in peer-to-peer or not.
    /// @return isPaused_ Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused_ Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor_ The reserve actor applied to this market.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            bool isCreated_,
            bool p2pDisabled_,
            bool isPaused_,
            bool isPartiallyPaused_,
            uint256 reserveFactor_
        )
    {
        Types.MarketStatus memory marketStatus_ = morpho.marketStatus(_poolTokenAddress);
        isCreated_ = marketStatus_.isCreated;
        p2pDisabled_ = morpho.p2pDisabled(_poolTokenAddress);
        isPaused_ = marketStatus_.isPaused;
        isPartiallyPaused_ = marketStatus_.isPartiallyPaused;
        reserveFactor_ = morpho.marketParameters(_poolTokenAddress).reserveFactor;
    }

    /// INTERNAL ///

    /// @notice Computes and returns new peer-to-peer indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function _computeP2PIndexes(Params memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        // Compute pool growth factors

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.rayDiv(
            _params.lastPoolSupplyIndex
        );
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.rayDiv(
            _params.lastPoolBorrowIndex
        );

        // Compute peer-to-peer growth factors

        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _params.p2pIndexCursor) *
            poolSupplyGrowthFactor +
            _params.p2pIndexCursor *
            poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
        uint256 p2pSupplyGrowthFactor = p2pGrowthFactor -
            (_params.reserveFactor * (p2pGrowthFactor - poolSupplyGrowthFactor)) /
            MAX_BASIS_POINTS;
        uint256 p2pBorrowGrowthFactor = p2pGrowthFactor +
            (_params.reserveFactor * (poolBorrowGrowthFactor - p2pGrowthFactor)) /
            MAX_BASIS_POINTS;

        // Compute new peer-to-peer supply index.

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pSupplyDelta.rayMul(_params.lastPoolSupplyIndex)).rayDiv(
                    (_params.delta.p2pSupplyAmount).rayMul(_params.lastP2PSupplyIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.rayMul(poolSupplyGrowthFactor)
            );
        }

        // Compute new peer-to-peer borrow index.

        if (_params.delta.p2pBorrowAmount == 0 || _params.delta.p2pBorrowDelta == 0) {
            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pBorrowDelta.rayMul(_params.poolBorrowIndex)).rayDiv(
                    (_params.delta.p2pBorrowAmount).rayMul(_params.lastP2PBorrowIndex)
                ),
                RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(
                (RAY - shareOfTheDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.rayMul(poolBorrowGrowthFactor)
            );
        }
    }

    /// @notice Computes and return the new peer-to-peer supply index.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    function _computeP2PSupplyIndex(Params memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex)
    {
        (uint256 p2pSupplyGrowthFactor, uint256 poolSupplyGrowthFactor, , ) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pIndexCursor
        );

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pSupplyDelta.rayMul(_params.lastPoolSupplyIndex)).rayDiv(
                    (_params.delta.p2pSupplyAmount).rayMul(_params.lastP2PSupplyIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.rayMul(poolSupplyGrowthFactor)
            );
        }
    }

    /// @notice Computes and return the new peer-to-peer borrow index.
    /// @param _params Computation parameters.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function _computeP2PBorrowIndex(Params memory _params)
        internal
        pure
        returns (uint256 newP2PBorrowIndex)
    {
        (, , uint256 p2pBorrowGrowthFactor, uint256 poolBorrowGrowthFactor) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pIndexCursor
        );

        if (_params.delta.p2pBorrowAmount == 0 || _params.delta.p2pBorrowDelta == 0) {
            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pBorrowDelta.rayMul(_params.poolBorrowIndex)).rayDiv(
                    (_params.delta.p2pBorrowAmount).rayMul(_params.lastP2PBorrowIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.rayMul(poolBorrowGrowthFactor)
            );
        }
    }

    /// @dev Computes and returns peer-to-peer supply growth factor and peer-to-peer borrow growth factor.
    /// @param _poolSupplyIndex The current pool supply index.
    /// @param _poolBorrowIndex The current pool borrow index.
    /// @param _lastPoolSupplyIndex The pool supply index at last update.
    /// @param _lastPoolBorrowIndex The pool borrow index at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return p2pSupplyGrowthFactor_ The peer-to-peer supply growth factor.
    /// @return poolSupplyGrowthFactor_ The pool supply growth factor.
    /// @return p2pBorrowGrowthFactor_ The peer-to-peer borrow growth factor.
    /// @return poolBorrowGrowthFactor_ The pool borrow growth factor.
    function _computeGrowthFactors(
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex,
        uint256 _lastPoolSupplyIndex,
        uint256 _lastPoolBorrowIndex,
        uint256 _reserveFactor,
        uint256 _p2pIndexCursor
    )
        internal
        pure
        returns (
            uint256 p2pSupplyGrowthFactor_,
            uint256 poolSupplyGrowthFactor_,
            uint256 p2pBorrowGrowthFactor_,
            uint256 poolBorrowGrowthFactor_
        )
    {
        poolSupplyGrowthFactor_ = _poolSupplyIndex.rayDiv(_lastPoolSupplyIndex);
        poolBorrowGrowthFactor_ = _poolBorrowIndex.rayDiv(_lastPoolBorrowIndex);

        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _p2pIndexCursor) *
            poolSupplyGrowthFactor_ +
            _p2pIndexCursor *
            poolBorrowGrowthFactor_) / MAX_BASIS_POINTS;

        p2pSupplyGrowthFactor_ =
            p2pGrowthFactor -
            (_reserveFactor * (p2pGrowthFactor - poolSupplyGrowthFactor_)) /
            MAX_BASIS_POINTS;
        p2pBorrowGrowthFactor_ =
            p2pGrowthFactor +
            (_reserveFactor * (poolBorrowGrowthFactor_ - p2pGrowthFactor)) /
            MAX_BASIS_POINTS;
    }

    /// @dev Computes and returns Compound's updated indexes.
    /// @param _poolTokenAddress The address of the market to compute.
    /// @return newSupplyIndex The updated supply index.
    /// @return newBorrowIndex The updated borrow index.
    function _computeCompoundsIndexes(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyIndex, uint256 newBorrowIndex)
    {
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        DataTypes.ReserveData memory reserve = lendingPool.getReserveData(underlyingAddress);

        if (block.timestamp == reserve.lastUpdateTimestamp)
            return (
                lendingPool.getReserveNormalizedIncome(underlyingAddress),
                lendingPool.getReserveNormalizedVariableDebt(underlyingAddress)
            );

        newSupplyIndex = calculateLinearInterest(
            reserve.currentLiquidityRate,
            reserve.lastUpdateTimestamp
        ).rayMul(reserve.liquidityIndex);

        newBorrowIndex = calculateCompoundedInterest(
            reserve.currentVariableBorrowRate,
            reserve.lastUpdateTimestamp
        ).rayMul(reserve.variableBorrowIndex);
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        return
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(
                getUpdatedP2PSupplyIndex(_poolTokenAddress)
            ) +
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(
                lendingPool.getReserveNormalizedIncome(
                    IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
                )
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        return
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(
                getUpdatedP2PBorrowIndex(_poolTokenAddress)
            ) +
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(
                lendingPool.getReserveNormalizedVariableDebt(
                    IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
                )
            );
    }

    function calculateLinearInterest(uint256 rate, uint256 lastUpdateTimestamp)
        internal
        view
        returns (uint256)
    {
        uint256 timeDifference = block.timestamp - lastUpdateTimestamp;

        return ((rate * timeDifference) / SECONDS_PER_YEAR) + WadRayMath.RAY;
    }

    function calculateCompoundedInterest(uint256 rate, uint256 lastUpdateTimestamp)
        public
        view
        returns (uint256)
    {
        return computeCompoundedInterest(rate, block.timestamp - lastUpdateTimestamp);
    }

    /// @dev calculates compounded interest over a period of time.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The APR to use in the computation.
    /// @param _elapsedTime The amount of time during to get the interest for.
    /// @return results in ray
    function computeCompoundedInterest(uint256 _rate, uint256 _elapsedTime)
        public
        pure
        returns (uint256)
    {
        uint256 rate = _rate / SECONDS_PER_YEAR;

        if (_elapsedTime == 0) return WadRayMath.RAY;

        if (_elapsedTime == 1) return WadRayMath.RAY + rate;

        uint256 ratePowerTwo = rate.rayMul(rate);
        uint256 ratePowerThree = ratePowerTwo.rayMul(rate);

        return
            WadRayMath.RAY +
            rate *
            _elapsedTime +
            (_elapsedTime * (_elapsedTime - 1) * ratePowerTwo) /
            2 +
            (_elapsedTime * (_elapsedTime - 1) * (_elapsedTime - 2) * ratePowerThree) /
            6;
    }
}
