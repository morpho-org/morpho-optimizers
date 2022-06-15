// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";
import "../interfaces/ILens.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../libraries/CompoundMath.sol";

import "./IndexesLens.sol";

/// @title UsersLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract UsersLens is IndexesLens {
    using CompoundMath for uint256;

    /// ERRORS ///

    /// @notice Thrown when the Compound's oracle failed.
    error CompoundOracleFailed();

    /// EXTERNAL ///

    /// @notice Returns all markets entered by a given user.
    /// @param _user The address of the user.
    /// @return enteredMarkets_ The list of markets entered by this user.
    function getEnteredMarkets(address _user)
        external
        view
        returns (address[] memory enteredMarkets_)
    {
        return morpho.getEnteredMarkets(_user);
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbEnteredMarkets = enteredMarkets.length;
        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            bool shouldUpdateIndexes;
            for (uint256 j; j < nbUpdatedMarkets; ) {
                if (_updatedMarkets[j] == poolTokenEntered) {
                    shouldUpdateIndexes = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                shouldUpdateIndexes,
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

    /// PUBLIC ///

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUpdatedUserSupplyBalance(address _user, address _poolTokenAddress)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (uint256 poolSupplyIndex, ) = _computePoolIndexes(_poolTokenAddress);

        balanceOnPool = morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.mul(
            poolSupplyIndex
        );
        balanceInP2P = morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.mul(
            getUpdatedP2PSupplyIndex(_poolTokenAddress)
        );

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUpdatedUserBorrowBalance(address _user, address _poolTokenAddress)
        public
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

    /// @notice Returns the supply rate per block a given user is currently experiencing on a given market.
    /// @param _user The user to compute the supply rate per block for.
    /// @param _poolTokenAddress The address of the market.
    /// @return The supply rate per block the user is currently experiencing (in wad).
    function getUpdatedUserSupplyRatePerBlock(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getUpdatedUserSupplyBalance(_user, _poolTokenAddress);
        if (totalBalance == 0) return 0;

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerBlock(_poolTokenAddress);

        return
            (poolSupplyRate.mul(balanceOnPool) + p2pSupplyRate.mul(balanceInP2P)).div(totalBalance);
    }

    /// @notice Returns the borrow rate per block a given user is currently experiencing on a given market.
    /// @param _user The user to compute the borrow rate per block for.
    /// @param _poolTokenAddress The address of the market.
    /// @return The borrow rate per block the user is currently experiencing (in wad).
    function getUpdatedUserBorrowRatePerBlock(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getUpdatedUserBorrowBalance(_user, _poolTokenAddress);
        if (totalBalance == 0) return 0;

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerBlock(_poolTokenAddress);

        return
            (poolBorrowRate.mul(balanceOnPool) + p2pBorrowRate.mul(balanceInP2P)).div(totalBalance);
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
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbEnteredMarkets = enteredMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, true, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, true, oracle);

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
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbEnteredMarkets = enteredMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                true,
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

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`, by optionally computing virtually updated pool and peer-to-peer indexes.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _computeUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        bool _computeUpdatedIndexes,
        ICompoundOracle _oracle
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolTokenAddress);
        if (assetData.underlyingPrice == 0) revert CompoundOracleFailed();

        (, assetData.collateralFactor, ) = comptroller.markets(_poolTokenAddress);

        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = getIndexes(_poolTokenAddress, _computeUpdatedIndexes);

        assetData.collateralValue = _computeUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
        ).mul(assetData.underlyingPrice);

        assetData.debtValue = _computeUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
        ).mul(assetData.underlyingPrice);

        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// @dev Checks whether the user has enough collateral to maintain such a borrow position.
    /// @param _user The user to check.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return isLiquidatable_ whether or not the user is liquidatable.
    function isLiquidatable(address _user, address[] memory _updatedMarkets)
        public
        view
        returns (bool)
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 maxDebtValue;
        uint256 debtValue;

        uint256 nbEnteredMarkets = enteredMarkets.length;
        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            bool shouldUpdateIndexes;
            for (uint256 j; j < nbUpdatedMarkets; ) {
                if (_updatedMarkets[j] == poolTokenEntered) {
                    shouldUpdateIndexes = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                shouldUpdateIndexes,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            unchecked {
                ++i;
            }
        }

        return debtValue > maxDebtValue;
    }

    /// @dev Computes the maximum repayable amount for a potential liquidation.
    /// @param _user The potential liquidatee.
    /// @param _poolTokenBorrowedAddress The address of the market to repay.
    /// @param _poolTokenCollateralAddress The address of the market to seize.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address[] calldata _updatedMarkets
    ) external view returns (uint256 toRepay) {
        address[] memory updatedMarkets = new address[](_updatedMarkets.length + 2);

        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbUpdatedMarkets; ) {
            updatedMarkets[i] = _updatedMarkets[i];

            unchecked {
                ++i;
            }
        }

        updatedMarkets[updatedMarkets.length - 2] = _poolTokenBorrowedAddress;
        updatedMarkets[updatedMarkets.length - 1] = _poolTokenCollateralAddress;
        if (!isLiquidatable(_user, updatedMarkets)) return 0;

        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());

        (, , uint256 totalCollateralBalance) = getUpdatedUserSupplyBalance(
            _user,
            _poolTokenCollateralAddress
        );
        (, , uint256 totalBorrowBalance) = getUpdatedUserBorrowBalance(
            _user,
            _poolTokenBorrowedAddress
        );

        uint256 borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        uint256 collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        if (borrowedPrice == 0 || collateralPrice == 0) revert CompoundOracleFailed();

        uint256 maxROIRepay = totalCollateralBalance.mul(collateralPrice).div(borrowedPrice).div(
            comptroller.liquidationIncentiveMantissa()
        );

        uint256 maxRepayable = totalBorrowBalance.mul(comptroller.closeFactorMantissa());

        toRepay = maxROIRepay > maxRepayable ? maxRepayable : maxROIRepay;
    }

    /// INTERNAL ///

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
}
