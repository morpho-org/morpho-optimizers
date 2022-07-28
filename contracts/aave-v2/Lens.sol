// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/IAToken.sol";
import "./interfaces/IMorpho.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@morpho-labs/data-structures/contracts/HeapOrdering.sol";
import "@morpho-labs/morpho-utils/math/PercentageMath.sol";
import "@morpho-labs/morpho-utils/math/WadRayMath.sol";
import "@morpho-labs/morpho-utils/math/Math.sol";

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
    ILendingPool public immutable pool;

    /// CONSTRUCTOR ///

    constructor(address _morphoAddress, ILendingPoolAddressesProvider _addressesProvider) {
        morpho = IMorpho(_morphoAddress);
        addressesProvider = _addressesProvider;
        pool = ILendingPool(addressesProvider.getLendingPool());
    }

    /// ERRORS ///

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// GETTERS ///

    /// @notice Checks if a market is created.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreated(address _poolTokenAddress) external view returns (bool) {
        return morpho.market(_poolTokenAddress).isCreated;
    }

    /// @notice Checks if a market is created and not paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view returns (bool) {
        Types.Market memory market = morpho.market(_poolTokenAddress);
        return market.isCreated && !market.isPaused;
    }

    /// @notice Checks if a market is created and not paused or partially paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created, not paused and not partially paused, otherwise false.
    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress)
        external
        view
        returns (bool)
    {
        Types.Market memory market = morpho.market(_poolTokenAddress);
        return market.isCreated && !market.isPaused && !market.isPartiallyPaused;
    }

    /// @notice Returns the current balance state of the user.
    /// @param _user The user to determine liquidity for.
    /// @return liquidityData The liquidity data of the user.
    function getUserBalanceStates(address _user)
        public
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
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        Types.LiquidityData memory data = getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
        Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
            _user,
            _poolTokenAddress,
            oracle
        );
        uint256 healthFactor = data.debtValue > 0
            ? data.liquidationThresholdValue.wadDiv(data.debtValue)
            : type(uint256).max;

        // Not possible to withdraw nor borrow.
        if (healthFactor <= HEALTH_FACTOR_LIQUIDATION_THRESHOLD) return (0, 0);

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
        address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();

        assetData.underlyingPrice = _oracle.getAssetPrice(underlyingToken); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = pool
        .getConfiguration(underlyingToken)
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
        address[] memory marketsCreated = morpho.getMarketsCreated();
        uint256 numberOfMarketsCreated = marketsCreated.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[i];

            if (_isSupplyingOrBorrowing(_user, poolToken)) {
                Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                    _user,
                    poolToken,
                    oracle
                );

                liquidityData.collateralValue += assetData.collateralValue;
                liquidityData.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
                liquidityData.liquidationThresholdValue += assetData.collateralValue.percentMul(
                    assetData.liquidationThreshold
                );
                liquidityData.debtValue += assetData.debtValue;

                if (_poolTokenAddress == poolToken) {
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
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns the hypothetical health factor of a user
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return healthFactor The health factor of the user.
    function getUserHypotheticalHealthFactor(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (uint256 healthFactor) {
        Types.LiquidityData memory liquidityData = getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        healthFactor = liquidityData.debtValue > 0
            ? liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue)
            : type(uint256).max;
    }

    /// @dev Returns the current health factor of a user
    /// @param _user The user to determine liquidity for.
    /// @return healthFactor The health factor of the user.
    function getUserHealthFactor(address _user) public view returns (uint256 healthFactor) {
        Types.LiquidityData memory liquidityData = getUserBalanceStates(_user);
        healthFactor = liquidityData.debtValue > 0
            ? liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue)
            : type(uint256).max;
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
            Types.Market memory market = morpho.market(_poolTokenAddress);

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                market.reserveFactor,
                market.p2pIndexCursor,
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
            Types.Market memory market = morpho.market(_poolTokenAddress);

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                market.reserveFactor,
                market.p2pIndexCursor,
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
            Types.Market memory market = morpho.market(_poolTokenAddress);

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                market.reserveFactor,
                market.p2pIndexCursor,
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
    /// @return isP2PDisabled_ Whether user are put in peer-to-peer or not.
    /// @return isPaused_ Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused_ Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor_ The reserve actor applied to this market.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            bool isCreated_,
            bool isP2PDisabled_,
            bool isPaused_,
            bool isPartiallyPaused_,
            uint256 reserveFactor_
        )
    {
        Types.Market memory market = morpho.market(_poolTokenAddress);
        isCreated_ = market.isCreated;
        isP2PDisabled_ = market.isP2PDisabled;
        isPaused_ = market.isPaused;
        isPartiallyPaused_ = market.isPartiallyPaused;
        reserveFactor_ = market.reserveFactor;
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

        (
            uint256 p2pSupplyGrowthFactor,
            uint256 poolSupplyGrowthFactor,
            uint256 p2pBorrowGrowthFactor,
            uint256 poolBorrowGrowthFactor
        ) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pIndexCursor
        );

        // Compute new peer-to-peer supply index.

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pSupplyDelta.wadToRay().rayMul(_params.lastPoolSupplyIndex))
                .rayDiv(
                    (_params.delta.p2pSupplyAmount.wadToRay()).rayMul(_params.lastP2PSupplyIndex)
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
                (_params.delta.p2pBorrowDelta.wadToRay().rayMul(_params.lastPoolBorrowIndex))
                .rayDiv(
                    (_params.delta.p2pBorrowAmount.wadToRay()).rayMul(_params.lastP2PBorrowIndex)
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
                (_params.delta.p2pSupplyDelta.wadToRay().rayMul(_params.lastPoolSupplyIndex))
                .rayDiv(
                    _params.delta.p2pSupplyAmount.wadToRay().rayMul(_params.lastP2PSupplyIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

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
                (_params.delta.p2pBorrowDelta.wadToRay().rayMul(_params.lastPoolBorrowIndex))
                .rayDiv(
                    _params.delta.p2pBorrowAmount.wadToRay().rayMul(_params.lastP2PBorrowIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

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

        uint256 p2pGrowthFactor = poolSupplyGrowthFactor_.percentMul(
            (MAX_BASIS_POINTS - _p2pIndexCursor)
        ) + poolBorrowGrowthFactor_.percentMul(_p2pIndexCursor);

        p2pSupplyGrowthFactor_ =
            p2pGrowthFactor -
            (p2pGrowthFactor - poolSupplyGrowthFactor_).percentMul(_reserveFactor);
        p2pBorrowGrowthFactor_ =
            p2pGrowthFactor +
            (poolBorrowGrowthFactor_ - p2pGrowthFactor).percentMul(_reserveFactor);
    }

    /// @dev Computes and returns Aave's updated indexes.
    /// @param _poolTokenAddress The address of the market to compute.
    /// @return newSupplyIndex The updated supply index.
    /// @return newBorrowIndex The updated borrow index.
    function _computePoolIndexes(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyIndex, uint256 newBorrowIndex)
    {
        address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        return (
            pool.getReserveNormalizedIncome(underlyingToken),
            pool.getReserveNormalizedVariableDebt(underlyingToken)
        );
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
                pool.getReserveNormalizedIncome(
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
                pool.getReserveNormalizedVariableDebt(
                    IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
                )
            );
    }

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(address _user, address _market) internal view returns (bool) {
        return
            morpho.userMarkets(_user) &
                (morpho.borrowMask(_market) | (morpho.borrowMask(_market) << 1)) !=
            0;
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
