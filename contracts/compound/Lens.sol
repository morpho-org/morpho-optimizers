// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IMorpho.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/CompoundMath.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice User accessible getters.
contract Lens {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct Params {
        uint256 lastP2PSupplyIndex; // The current peer-to-peer supply index.
        uint256 lastP2PBorrowIndex; // The current peer-to-peer borrow index
        uint256 poolSupplyIndex; // The current pool supply index
        uint256 poolBorrowIndex; // The pool supply index at last update.
        uint256 lastPoolSupplyIndex; // The pool supply index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }

    struct RateParams {
        uint256 p2pIndex; // The peer-to-peer index.
        uint256 poolIndex; // The pool index.
        uint256 lastPoolIndex; // The pool index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pAmount; // Sum of all stored peer-to-peer balance in supply or borrow (in peer-to-peer unit).
        uint256 p2pDelta; // Sum of all stored peer-to-peer in supply or borrow (in peer-to-peer unit).
    }

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant WAD = 1e18;
    IMorpho public immutable morpho;

    /// CONSTRUCTOR ///

    constructor(address _morphoAddress) {
        morpho = IMorpho(_morphoAddress);
    }

    /// ERRORS ///

    /// @notice Thrown when the Compound's oracle failed.
    error CompoundOracleFailed();

    ///////////////////////////////////
    ///           GETTERS           ///
    ///////////////////////////////////

    /// MARKET STATUSES ///

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

    /// MARKET INFO ///

    /// @notice Returns market's data.
    /// @return p2pSupplyIndex_ The peer-to-peer supply index of the market.
    /// @return p2pBorrowIndex_ The peer-to-peer borrow index of the market.
    /// @return lastUpdateBlockNumber_ The last block number when peer-to-peer indexes where updated.
    /// @return p2pSupplyDelta_ The peer-to-peer supply delta (in scaled balance).
    /// @return p2pBorrowDelta_ The peer-to-peer borrow delta (in cdUnit).
    /// @return p2pSupplyAmount_ The peer-to-peer supply amount (in peer-to-peer unit).
    /// @return p2pBorrowAmount_ The peer-to-peer borrow amount (in peer-to-peer unit).
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
        lastUpdateBlockNumber_ = morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber;
    }

    /// @notice Returns market's configuration.
    /// @return underlying_ The underlying token address.
    /// @return isCreated_ Whether the market is created or not.
    /// @return p2pDisabled_ Whether user are put in peer-to-peer or not.
    /// @return isPaused_ Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused_ Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor_ The reserve actor applied to this market.
    /// @return collateralFactor_ The pool collateral factor also used by Morpho
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
        )
    {
        underlying_ = ICToken(_poolTokenAddress).underlying();
        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        isCreated_ = marketStatus.isCreated;
        p2pDisabled_ = morpho.p2pDisabled(_poolTokenAddress);
        isPaused_ = marketStatus.isPaused;
        isPartiallyPaused_ = marketStatus.isPartiallyPaused;
        reserveFactor_ = morpho.marketParameters(_poolTokenAddress).reserveFactor;
        (, collateralFactor_, ) = morpho.comptroller().markets(_poolTokenAddress);
    }

    /// BALANCES ///

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 i;

        while (i < enteredMarkets.length) {
            address poolTokenEntered = enteredMarkets[i];
            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            collateralValue += assetData.collateralValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The unlockable balance of the user (in underlying).
    /// @return balanceInP2P The matched balance of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUserBorrowBalance(address _user, address _poolTokenAddress)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (, uint256 newBorrowIndex) = _computePoolIndexes(_poolTokenAddress);
        balanceOnPool = morpho.borrowBalanceInOf(_poolTokenAddress, _user).onPool.mul(
            newBorrowIndex
        );
        balanceInP2P = morpho.borrowBalanceInOf(_poolTokenAddress, _user).inP2P.mul(
            getUpdatedP2PBorrowIndex(_poolTokenAddress)
        );
        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The unlockable balance of the user (in underlying).
    /// @return balanceInP2P The matched balance of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUserSupplyBalance(address _user, address _poolTokenAddress)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (uint256 newSupplyIndex, ) = _computePoolIndexes(_poolTokenAddress);
        balanceOnPool = morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.mul(
            newSupplyIndex
        );
        balanceInP2P = morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.mul(
            getUpdatedP2PSupplyIndex(_poolTokenAddress)
        );
        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
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
        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 i;

        while (i < enteredMarkets.length) {
            address poolTokenEntered = enteredMarkets[i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.maxDebtValue += assetData.maxDebtValue;
        data.debtValue += assetData.debtValue;

        // Not possible to withdraw nor borrow.
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = (data.maxDebtValue - data.debtValue).div(
            assetData.underlyingPrice
        );

        withdrawable = assetData.collateralValue.div(assetData.underlyingPrice);
        if (assetData.collateralFactor != 0) {
            withdrawable = Math.min(
                withdrawable,
                differenceInUnderlying.div(assetData.collateralFactor)
            );
        }

        borrowable = differenceInUnderlying;
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolTokenAddress);
        (, assetData.collateralFactor, ) = morpho.comptroller().markets(_poolTokenAddress);

        (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        ) = getUpdatedIndexes(_poolTokenAddress);

        assetData.collateralValue = _computeUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            newP2PSupplyIndex,
            newPoolSupplyIndex
        ).mul(assetData.underlyingPrice);

        assetData.debtValue = _computeUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            newP2PBorrowIndex,
            newPoolBorrowIndex
        ).mul(assetData.underlyingPrice);

        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum debt value possible of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (uint256 debtValue, uint256 maxDebtValue) {
        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 i;

        while (i < enteredMarkets.length) {
            address poolTokenEntered = enteredMarkets[i];

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            unchecked {
                ++i;
            }

            if (_poolTokenAddress == poolTokenEntered) {
                if (_borrowedAmount > 0)
                    debtValue += _borrowedAmount.mul(assetData.underlyingPrice);

                if (_withdrawnAmount > 0)
                    maxDebtValue -= _withdrawnAmount.mul(assetData.underlyingPrice).mul(
                        assetData.collateralFactor
                    );
            }
        }
    }

    /// INDEXES ///

    /// @notice Returns the updated peer-to-peer indexes.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    /// @return newP2PBorrowIndex The peer-to-peer supply index after update.
    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        (newP2PSupplyIndex, newP2PBorrowIndex, , ) = getUpdatedIndexes(_poolTokenAddress);
    }

    /// @notice Returns the updated pool indexes.
    /// @param _poolTokenAddress The address of the market.
    /// @return newPoolSupplyIndex_ The pool supply index after update.
    /// @return newPoolBorrowIndex_ The pool supply index after update.
    function getUpdatedPoolIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256 newPoolSupplyIndex_, uint256 newPoolBorrowIndex_)
    {
        return _computePoolIndexes(_poolTokenAddress);
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber)
            return morpho.p2pSupplyIndex(_poolTokenAddress);
        else {
            Types.LastPoolIndexes memory poolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 poolSupplyIndex, uint256 poolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            return _computeP2PSupplyIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PBorrowIndex The peer-to-peer  index after update.
    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber)
            return morpho.p2pBorrowIndex(_poolTokenAddress);
        else {
            Types.LastPoolIndexes memory poolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 poolSupplyIndex, uint256 poolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            return _computeP2PBorrowIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    /// @return newP2PBorrowIndex The peer-to-peer borrow index after update.
    /// @return newPoolSupplyIndex The pool supply index after update.
    /// @return newPoolBorrowIndex The pool borrow index after update.
    function getUpdatedIndexes(address _poolTokenAddress)
        public
        view
        returns (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        )
    {
        (newPoolSupplyIndex, newPoolBorrowIndex) = _computePoolIndexes(_poolTokenAddress);

        if (block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber) {
            newP2PSupplyIndex = morpho.p2pSupplyIndex(_poolTokenAddress);
            newP2PBorrowIndex = morpho.p2pBorrowIndex(_poolTokenAddress);
        } else {
            Types.LastPoolIndexes memory poolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            Params memory params = Params(
                morpho.p2pSupplyIndex(_poolTokenAddress),
                morpho.p2pBorrowIndex(_poolTokenAddress),
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                morpho.deltas(_poolTokenAddress)
            );

            (newP2PSupplyIndex, newP2PBorrowIndex) = _computeP2PIndexes(params);
        }
    }

    /// LIQUIDATION ///

    /// @dev Checks whether the user has enough collateral to maintain such a borrow position.
    /// @param _user The user to check.
    /// @return isLiquidable_ wheter or not the user is liquidable.
    function isLiquidable(address _user) external view returns (bool) {
        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);
        uint256 numberOfEnteredMarkets = enteredMarkets.length;

        uint256 maxDebtValue;
        uint256 debtValue;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[i];

            Types.AssetLiquidityData memory assetData = _computeUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            ++i;
        }
        return debtValue > maxDebtValue;
    }

    ////////////////////////////////////
    ///           INTERNAL           ///
    ////////////////////////////////////

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _computeUserSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    ) internal view returns (uint256) {
        return
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.mul(_p2pSupplyIndex) +
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.mul(_poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _computeUserBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    ) internal view returns (uint256) {
        return
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).inP2P.mul(_p2pBorrowIndex) +
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).onPool.mul(_poolBorrowIndex);
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function _computeUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) internal view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolTokenAddress);
        if (assetData.underlyingPrice == 0) revert CompoundOracleFailed();
        (, assetData.collateralFactor, ) = morpho.comptroller().markets(_poolTokenAddress);
        (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        ) = getUpdatedIndexes(_poolTokenAddress);

        assetData.collateralValue = _computeUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            newP2PSupplyIndex,
            newPoolSupplyIndex
        ).mul(assetData.underlyingPrice);
        assetData.debtValue = _computeUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            newP2PBorrowIndex,
            newPoolBorrowIndex
        ).mul(assetData.underlyingPrice);
        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// INDEXES ///

    /// @dev Computes and returns Compound's updated indexes.
    /// @param _poolTokenAddress The address of the market to compute.
    /// @return newSupplyIndex The updated supply index.
    /// @return newBorrowIndex The updated borrow index.
    function _computePoolIndexes(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyIndex, uint256 newBorrowIndex)
    {
        ICToken cToken = ICToken(_poolTokenAddress);
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (block.number == accrualBlockNumberPrior)
            return (cToken.exchangeRateStored(), cToken.borrowIndex());

        // Read the previous values out of storage
        uint256 cashPrior = cToken.getCash();
        uint256 totalSupply = cToken.totalSupply();
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();
        uint256 borrowIndexPrior = cToken.borrowIndex();

        // Calculate the current borrow interest rate
        uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );
        require(borrowRateMantissa <= 0.0005e16, "borrow rate is absurdly high");

        uint256 blockDelta = block.number - accrualBlockNumberPrior;

        // Calculate the interest accumulated into borrows and reserves and the new index.
        uint256 simpleInterestFactor = borrowRateMantissa * blockDelta;
        uint256 interestAccumulated = simpleInterestFactor.mul(borrowsPrior);
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew = cToken.reserveFactorMantissa().mul(interestAccumulated) +
            reservesPrior;

        newSupplyIndex = totalSupply > 0
            ? (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply)
            : cToken.initialExchangeRateMantissa();
        newBorrowIndex = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }

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

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.div(_params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.div(_params.lastPoolBorrowIndex);

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

        // Compute new peer-to-peer supply index

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.mul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.delta.p2pSupplyDelta.mul(_params.lastPoolSupplyIndex)).div(
                    (_params.delta.p2pSupplyAmount).mul(_params.lastP2PSupplyIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex = _params.lastP2PSupplyIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.mul(poolSupplyGrowthFactor)
            );
        }

        // Compute new peer-to-peer borrow index

        if (_params.delta.p2pBorrowAmount == 0 || _params.delta.p2pBorrowDelta == 0) {
            newP2PBorrowIndex = _params.lastP2PBorrowIndex.mul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.delta.p2pBorrowDelta.mul(_params.poolBorrowIndex)).div(
                    (_params.delta.p2pBorrowAmount).mul(_params.lastP2PBorrowIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.mul(poolBorrowGrowthFactor)
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
        // Compute pool growth factors

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.div(_params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.div(_params.lastPoolBorrowIndex);

        // Compute peer-to-peer growth factors

        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _params.p2pIndexCursor) *
            poolSupplyGrowthFactor +
            _params.p2pIndexCursor *
            poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
        uint256 p2pSupplyGrowthFactor = p2pGrowthFactor -
            (_params.reserveFactor * (p2pGrowthFactor - poolSupplyGrowthFactor)) /
            MAX_BASIS_POINTS;

        // Compute new peer-to-peer supply index

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.mul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.delta.p2pSupplyDelta.mul(_params.lastPoolSupplyIndex)).div(
                    (_params.delta.p2pSupplyAmount).mul(_params.lastP2PSupplyIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex = _params.lastP2PSupplyIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.mul(poolSupplyGrowthFactor)
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
        // Compute pool growth factors

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.div(_params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.div(_params.lastPoolBorrowIndex);

        // Compute peer-to-peer growth factors

        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _params.p2pIndexCursor) *
            poolSupplyGrowthFactor +
            _params.p2pIndexCursor *
            poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
        uint256 p2pBorrowGrowthFactor = p2pGrowthFactor +
            (_params.reserveFactor * (poolBorrowGrowthFactor - p2pGrowthFactor)) /
            MAX_BASIS_POINTS;

        // Compute new peer-to-peer borrow index

        if (_params.delta.p2pBorrowAmount == 0 || _params.delta.p2pBorrowDelta == 0) {
            newP2PBorrowIndex = _params.lastP2PBorrowIndex.mul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.delta.p2pBorrowDelta.mul(_params.poolBorrowIndex)).div(
                    (_params.delta.p2pBorrowAmount).mul(_params.lastP2PBorrowIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.mul(poolBorrowGrowthFactor)
            );
        }
    }
}
