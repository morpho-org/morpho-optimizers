// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "./libraries/aave/ReserveConfiguration.sol";
import "./libraries/aave/UserConfiguration.sol";
import "./libraries/HeapOrdering2.sol";
import "./libraries/MarketLib.sol";

import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";
import {IVariableDebtToken} from "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@morpho-dao/morpho-utils/DelegateCall.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";

import "./MorphoStorage.sol";
import "./EventsAndErrors.sol";

/// @title MorphoUtils.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Modifiers, getters and other util functions for Morpho.
abstract contract MorphoUtils is MorphoStorage, EventsAndErrors {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using HeapOrdering2 for HeapOrdering.HeapArray;
    using SafeTransferLib for ERC20;
    using PercentageMath for uint256;
    using MarketLib for Types.Market;
    using DelegateCall for address;
    using WadRayMath for uint256;
    using Math for uint256;

    /// @notice Prevents to update a market not created yet.
    /// @param _poolToken The address of the market to check.
    modifier isMarketCreated(address _poolToken) {
        if (!market[_poolToken].isCreated()) revert MarketNotCreated();
        _;
    }

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(bytes32 _userMarkets, bytes32 _borrowMask)
        internal
        pure
        returns (bool)
    {
        return _userMarkets & (_borrowMask | (_borrowMask << 1)) != 0;
    }

    /// @dev Returns if a user is borrowing on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been borrowing on this market, false otherwise.
    function _isBorrowing(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & _borrowMask != 0;
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function _isSupplying(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & (_borrowMask << 1) != 0;
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function _isBorrowingAny(bytes32 _userMarkets) internal pure returns (bool) {
        return _userMarkets & BORROWING_MASK != 0;
    }

    /// @dev Returns if a user is borrowing on a given market and supplying on another given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowedBorrowMask The borrow mask of the market to check whether the user is borrowing.
    /// @param _suppliedBorrowMask The borrow mask of the market to check whether the user is supplying.
    /// @return True if the user is borrowing on the given market and supplying on the other given market, false otherwise.
    function _isBorrowingAndSupplying(
        bytes32 _userMarkets,
        bytes32 _borrowedBorrowMask,
        bytes32 _suppliedBorrowMask
    ) internal pure returns (bool) {
        bytes32 targetMask = _borrowedBorrowMask | (_suppliedBorrowMask << 1);
        return _userMarkets & targetMask == targetMask;
    }

    /// @notice Sets if the user is borrowing on a market.
    /// @param _user The user to set for.
    /// @param _borrowMask The borrow mask of the market to mark as borrowed.
    /// @param _borrowing True if the user is borrowing, false otherwise.
    function _setBorrowing(
        address _user,
        bytes32 _borrowMask,
        bool _borrowing
    ) internal {
        if (_borrowing) userMarkets[_user] |= _borrowMask;
        else userMarkets[_user] &= ~_borrowMask;
    }

    /// @notice Sets if the user is supplying on a market.
    /// @param _user The user to set for.
    /// @param _borrowMask The borrow mask of the market to mark as supplied.
    /// @param _supplying True if the user is supplying, false otherwise.
    function _setSupplying(
        address _user,
        bytes32 _borrowMask,
        bool _supplying
    ) internal {
        if (_supplying) userMarkets[_user] |= _borrowMask << 1;
        else userMarkets[_user] &= ~(_borrowMask << 1);
    }

    /// @dev Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function _updateIndexes(address _poolToken) internal {
        address(interestRatesManager).functionDelegateCall(
            abi.encodeWithSelector(interestRatesManager.updateIndexes.selector, _poolToken)
        );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        (uint256 inP2P, uint256 onPool) = _supplyBalanceInOf(_poolToken, _user);
        return
            inP2P.rayMul(p2pSupplyIndex[_poolToken]) +
            onPool.rayMul(poolIndexes[_poolToken].poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        (uint256 inP2P, uint256 onPool) = _borrowBalanceInOf(_poolToken, _user);
        return
            inP2P.rayMul(p2pBorrowIndex[_poolToken]) +
            onPool.rayMul(poolIndexes[_poolToken].poolBorrowIndex);
    }

    /// @dev Calculates the value of the collateral.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _collateralValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 collateral) {
        collateral = (_getUserSupplyBalanceInOf(_poolToken, _user) * _underlyingPrice) / _tokenUnit;
    }

    /// @dev Calculates the value of the debt.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _debtValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 debt) {
        debt = (_getUserBorrowBalanceInOf(_poolToken, _user) * _underlyingPrice).divUp(_tokenUnit);
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @param _user The user address.
    /// @param _poolToken The pool token that is being borrowed or withdrawn.
    /// @param _amountWithdrawn The amount that is being withdrawn.
    /// @param _amountBorrowed The amount that is being borrowed.
    /// @return values The struct containing health factor, collateral, debt, ltv, liquidation threshold values.
    function _liquidityData(
        address _user,
        address _poolToken,
        uint256 _amountWithdrawn,
        uint256 _amountBorrowed
    ) internal returns (Types.LiquidityData memory values) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        Types.AssetLiquidityData memory assetData;
        Types.LiquidityStackVars memory vars;

        DataTypes.UserConfigurationMap memory morphoPoolConfig = pool.getUserConfiguration(
            address(this)
        );
        vars.poolTokensLength = marketsCreated.length;
        vars.userMarkets = userMarkets[_user];

        for (uint256 i; i < vars.poolTokensLength; ++i) {
            vars.poolToken = marketsCreated[i];
            vars.borrowMask = borrowMask[vars.poolToken];

            if (!_isSupplyingOrBorrowing(vars.userMarkets, vars.borrowMask)) continue;

            vars.underlyingToken = market[vars.poolToken].underlyingToken;
            vars.underlyingPrice = oracle.getAssetPrice(vars.underlyingToken);

            if (vars.poolToken != _poolToken) _updateIndexes(vars.poolToken);

            (assetData.ltv, assetData.liquidationThreshold, , assetData.decimals, , ) = pool
            .getConfiguration(vars.underlyingToken)
            .getParams();

            // LTV should be zero if Morpho has not enabled this asset as collateral
            if (!morphoPoolConfig.isUsingAsCollateral(pool.getReserveData(vars.underlyingToken).id))
                assetData.ltv = 0;

            // If a LTV has been reduced to 0 on Aave v3, the other assets of the collateral are frozen.
            // In response, Morpho disables the asset as collateral and sets its liquidation threshold to 0.
            if (assetData.ltv == 0) assetData.liquidationThreshold = 0;

            unchecked {
                assetData.tokenUnit = 10**assetData.decimals;
            }

            if (_isBorrowing(vars.userMarkets, vars.borrowMask)) {
                values.debt += _debtValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
            }

            // Cache current asset collateral value.
            uint256 assetCollateralValue;
            if (_isSupplying(vars.userMarkets, vars.borrowMask)) {
                assetCollateralValue = _collateralValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
                values.collateral += assetCollateralValue;
                // Calculate LTV for borrow.
                values.maxDebt += assetCollateralValue.percentMul(assetData.ltv);
            }

            // Update debt variable for borrowed token.
            if (_poolToken == vars.poolToken && _amountBorrowed > 0)
                values.debt += (_amountBorrowed * vars.underlyingPrice).divUp(assetData.tokenUnit);

            // Update LT variable for withdraw.
            if (assetCollateralValue > 0)
                values.liquidationThreshold += assetCollateralValue.percentMul(
                    assetData.liquidationThreshold
                );

            // Subtract withdrawn amount from liquidation threshold and collateral.
            if (_poolToken == vars.poolToken && _amountWithdrawn > 0) {
                uint256 withdrawn = (_amountWithdrawn * vars.underlyingPrice) / assetData.tokenUnit;
                values.collateral -= withdrawn;
                values.liquidationThreshold -= withdrawn.percentMul(assetData.liquidationThreshold);
                values.maxDebt -= withdrawn.percentMul(assetData.ltv);
            }
        }
    }

    function _supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IEntryPositionsManager.supplyLogic.selector,
                _poolToken,
                msg.sender,
                _onBehalf,
                _amount,
                _maxGasForMatching
            )
        );
    }

    function _borrow(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IEntryPositionsManager.borrowLogic.selector,
                _poolToken,
                _amount,
                _maxGasForMatching
            )
        );
    }

    function _withdraw(
        address _poolToken,
        uint256 _amount,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        address(exitPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IExitPositionsManager.withdrawLogic.selector,
                _poolToken,
                _amount,
                msg.sender,
                _receiver,
                _maxGasForMatching
            )
        );
    }

    function _repay(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        address(exitPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IExitPositionsManager.repayLogic.selector,
                _poolToken,
                msg.sender,
                _onBehalf,
                _amount,
                _maxGasForMatching
            )
        );
    }

    // inP2P and onPool are reversed in this POC because that is what the type originally was. This should be changed.
    function _supplyBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256 inP2P, uint256 onPool)
    {
        onPool = suppliersOnPool[_poolToken].getValueOf(_user);
        inP2P = suppliersInP2P[_poolToken].getValueOf(_user);
    }

    function _borrowBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256 inP2P, uint256 onPool)
    {
        onPool = borrowersOnPool[_poolToken].getValueOf(_user);
        inP2P = borrowersInP2P[_poolToken].getValueOf(_user);
    }

    /// @notice Matches suppliers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects Aave's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        return
            _match(
                suppliersOnPool[_poolToken],
                suppliersInP2P[_poolToken],
                Types.MatchVars(
                    _poolToken,
                    poolIndexes[_poolToken].poolSupplyIndex,
                    p2pSupplyIndex[_poolToken],
                    _amount,
                    _maxGasForMatching,
                    false,
                    true
                )
            );
    }

    /// @notice Matches borrowers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects stored indexes to have been updated
    /// @param _poolToken The address of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        return
            _match(
                borrowersOnPool[_poolToken],
                borrowersInP2P[_poolToken],
                Types.MatchVars(
                    _poolToken,
                    poolIndexes[_poolToken].poolBorrowIndex,
                    p2pBorrowIndex[_poolToken],
                    _amount,
                    _maxGasForMatching,
                    true,
                    true
                )
            );
    }

    /// @notice Unmatches suppliers' liquidity in peer-to-peer up to the given `_amount` and moves it to Aave.
    /// @dev Note: This function expects Aave's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return unmatched The amount unmatched (in underlying).
    function _unmatchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 unmatched) {
        (unmatched, ) = _match(
            suppliersOnPool[_poolToken],
            suppliersInP2P[_poolToken],
            Types.MatchVars(
                _poolToken,
                poolIndexes[_poolToken].poolSupplyIndex,
                p2pSupplyIndex[_poolToken],
                _amount,
                _maxGasForMatching,
                false,
                false
            )
        );
    }

    /// @notice Unmatches borrowers' liquidity in peer-to-peer for the given `_amount` and moves it to Aave.
    /// @dev Note: This function expects and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return unmatched The amount unmatched (in underlying).
    function _unmatchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 unmatched) {
        (unmatched, ) = _match(
            borrowersOnPool[_poolToken],
            borrowersInP2P[_poolToken],
            Types.MatchVars(
                _poolToken,
                poolIndexes[_poolToken].poolBorrowIndex,
                p2pBorrowIndex[_poolToken],
                _amount,
                _maxGasForMatching,
                true,
                false
            )
        );
    }

    /// @param _heapOnPool The heap for the pool.
    /// @param _heapInP2P The heap for P2P.
    /// @param _vars The struct of working variables.
    function _match(
        HeapOrdering.HeapArray storage _heapOnPool,
        HeapOrdering.HeapArray storage _heapInP2P,
        Types.MatchVars memory _vars
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_vars.maxGasForMatching == 0) return (0, 0);

        address firstUser;
        uint256 remainingToMatch = _vars.amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        // prettier-ignore
        // This function will be used to decide whether to use the algorithm for matching or for unmatching.
        function(uint256, uint256, uint256, uint256, uint256)
            pure returns (uint256, uint256, uint256) f;
        HeapOrdering.HeapArray storage workingHeap;

        if (_vars.matching) {
            workingHeap = _heapOnPool;
            f = _matchStep;
        } else {
            workingHeap = _heapInP2P;
            f = _unmatchStep;
        }

        while (remainingToMatch > 0 && (firstUser = workingHeap.getHead()) != address(0)) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _vars.maxGasForMatching) break;
            }
            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remainingToMatch) = f(
                _heapOnPool.getValueOf(firstUser),
                _heapInP2P.getValueOf(firstUser),
                _vars.poolIndex,
                _vars.p2pIndex,
                remainingToMatch
            );

            if (!_vars.borrow) _updateSupplierInDS(_vars.poolToken, firstUser, onPool, inP2P);
            else _updateBorrowerInDS(_vars.poolToken, firstUser, onPool, inP2P);

            emit PositionUpdated(_vars.borrow, firstUser, _vars.poolToken, onPool, inP2P);
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _vars.amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
    }

    function _matchStep(
        uint256 _poolBalance,
        uint256 _p2pBalance,
        uint256 _poolIndex,
        uint256 _p2pIndex,
        uint256 _remaining
    )
        internal
        pure
        returns (
            uint256 newPoolBalance,
            uint256 newP2PBalance,
            uint256 remaining
        )
    {
        uint256 toProcess = Math.min(_poolBalance.rayMul(_poolIndex), _remaining);
        remaining = _remaining - toProcess;
        newPoolBalance = _poolBalance - toProcess.rayDiv(_poolIndex);
        newP2PBalance = _p2pBalance + toProcess.rayDiv(_p2pIndex);
    }

    function _unmatchStep(
        uint256 _poolBalance,
        uint256 _p2pBalance,
        uint256 _poolIndex,
        uint256 _p2pIndex,
        uint256 _remaining
    )
        internal
        pure
        returns (
            uint256 newPoolBalance,
            uint256 newP2PBalance,
            uint256 remaining
        )
    {
        uint256 toProcess = Math.min(_p2pBalance.rayMul(_p2pIndex), _remaining);
        remaining = _remaining - toProcess;
        newPoolBalance = _poolBalance + toProcess.rayDiv(_poolIndex);
        newP2PBalance = _p2pBalance - toProcess.rayDiv(_p2pIndex);
    }

    /// @param _token The market to update for the rewards manager. Should be the aToken for a supply, and the variable debt token for a borrow.
    /// @param _user The user.
    /// @param _marketOnPool The data structure of the pool market. Pass in the supplier or borrower pool heap.
    /// @param _marketInP2P The data structure of the P2P market. Pass in the supplier or borrower P2P heap.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateInDS(
        address _token,
        address _user,
        HeapOrdering.HeapArray storage _marketOnPool,
        HeapOrdering.HeapArray storage _marketInP2P,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        uint256 formerOnPool = _marketOnPool.getValueOf(_user);

        if (onPool != formerOnPool) {
            if (address(rewardsManager) != address(0))
                rewardsManager.updateUserAssetAndAccruedRewards(
                    rewardsController,
                    _user,
                    _token,
                    formerOnPool,
                    IScaledBalanceToken(_token).scaledTotalSupply()
                );
            _marketOnPool.update(_user, onPool, maxSortedUsers);
        }
        _marketInP2P.update(_user, inP2P, maxSortedUsers);
    }

    /// @notice Updates the given `_user`'s position in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateSupplierInDS(
        address _poolToken,
        address _user,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        _updateInDS(
            _poolToken,
            _user,
            suppliersOnPool[_poolToken],
            suppliersInP2P[_poolToken],
            onPool,
            inP2P
        );
    }

    /// @notice Updates the given `_user`'s position in the borrower data structures.
    /// @param _poolToken The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateBorrowerInDS(
        address _poolToken,
        address _user,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        address variableDebtTokenAddress = pool
        .getReserveData(market[_poolToken].underlyingToken)
        .variableDebtTokenAddress;

        _updateInDS(
            variableDebtTokenAddress,
            _user,
            borrowersOnPool[_poolToken],
            borrowersInP2P[_poolToken],
            onPool,
            inP2P
        );
    }

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        pool.supply(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _poolToken The address of the market.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(
        ERC20 _underlyingToken,
        address _poolToken,
        uint256 _amount
    ) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        _amount = Math.min(IAToken(_poolToken).balanceOf(address(this)), _amount);
        pool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        pool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        if (
            _amount == 0 ||
            IVariableDebtToken(
                pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this)) ==
            0
        ) return;

        pool.repay(address(_underlyingToken), _amount, VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }

    /// @notice Sets all pause statuses for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function _setPauseStatus(address _poolToken, bool _isPaused) internal {
        Types.Market storage market = market[_poolToken];

        market.isSupplyPaused = _isPaused;
        market.isBorrowPaused = _isPaused;
        market.isWithdrawPaused = _isPaused;
        market.isRepayPaused = _isPaused;
        market.isLiquidateCollateralPaused = _isPaused;
        market.isLiquidateBorrowPaused = _isPaused;

        emit IsSupplyPausedSet(_poolToken, _isPaused);
        emit IsBorrowPausedSet(_poolToken, _isPaused);
        emit IsWithdrawPausedSet(_poolToken, _isPaused);
        emit IsRepayPausedSet(_poolToken, _isPaused);
        emit IsLiquidateCollateralPausedSet(_poolToken, _isPaused);
        emit IsLiquidateBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Computes and returns new peer-to-peer indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function _computeP2PIndexes(Types.IRMParams memory _params)
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

        // Compute peer-to-peer growth factors.

        uint256 p2pSupplyGrowthFactor;
        uint256 p2pBorrowGrowthFactor;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = PercentageMath.weightedAvg(
                poolSupplyGrowthFactor,
                poolBorrowGrowthFactor,
                _params.p2pIndexCursor
            );

            p2pSupplyGrowthFactor =
                p2pGrowthFactor -
                (p2pGrowthFactor - poolSupplyGrowthFactor).percentMul(_params.reserveFactor);
            p2pBorrowGrowthFactor =
                p2pGrowthFactor +
                (poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(_params.reserveFactor);
        } else {
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone has done a flashloan on Aave, or because the interests
            // generated by the stable rate borrowing are high (making the supply rate higher than the variable borrow rate). In this case the peer-to-peer
            // growth factors are set to the pool borrow growth factor.
            p2pSupplyGrowthFactor = poolBorrowGrowthFactor;
            p2pBorrowGrowthFactor = poolBorrowGrowthFactor;
        }

        // Compute new peer-to-peer supply index.

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pSupplyDelta.rayMul(_params.lastPoolSupplyIndex)).rayDiv(
                    _params.delta.p2pSupplyAmount.rayMul(_params.lastP2PSupplyIndex)
                ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

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
                (_params.delta.p2pBorrowDelta.rayMul(_params.lastPoolBorrowIndex)).rayDiv(
                    _params.delta.p2pBorrowAmount.rayMul(_params.lastP2PBorrowIndex)
                ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.rayMul(poolBorrowGrowthFactor)
            );
        }
    }

    /// @dev Checks whether the user can borrow or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically borrow in.
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return Whether the borrow is allowed or not.
    function _borrowAllowed(
        address _user,
        address _poolToken,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // In response, Morpho mirrors this behavior.
        address priceOracleSentinel = addressesProvider.getPriceOracleSentinel();
        if (
            priceOracleSentinel != address(0) &&
            !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()
        ) return false;

        Types.LiquidityData memory values = _liquidityData(_user, _poolToken, 0, _borrowedAmount);
        return values.debt <= values.maxDebt;
    }

    /// @dev Implements withdraw logic without security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _unsafeWithdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        Types.WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolSupplyIndex = poolIndexes[_poolToken].poolSupplyIndex;

        (uint256 inP2P, uint256 onPool) = _supplyBalanceInOf(_poolToken, _supplier);

        /// Pool withdraw ///

        // Withdraw supply on pool.
        vars.onPoolSupply = onPool;
        if (vars.onPoolSupply > 0) {
            vars.toWithdraw = Math.min(
                vars.onPoolSupply.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            onPool -= Math.min(vars.onPoolSupply, vars.toWithdraw.rayDiv(vars.poolSupplyIndex));

            if (vars.remainingToWithdraw == 0) {
                _updateSupplierInDS(_poolToken, _supplier, onPool, inP2P);

                if (inP2P == 0 && onPool == 0)
                    _setSupplying(_supplier, borrowMask[_poolToken], false);

                _withdrawFromPool(underlyingToken, _poolToken, vars.toWithdraw); // Reverts on error.
                underlyingToken.safeTransfer(_receiver, _amount);

                emit Withdrawn(_supplier, _receiver, _poolToken, _amount, onPool, inP2P);

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];

        inP2P -= Math.min(inP2P, vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)); // In peer-to-peer supply unit.
        _updateSupplierInDS(_poolToken, _supplier, onPool, inP2P);

        // Reduce the peer-to-peer supply delta.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw
            ); // In underlying.

            delta.p2pSupplyDelta = delta.p2pSupplyDelta.zeroFloorSub(
                vars.remainingToWithdraw.rayDiv(vars.poolSupplyIndex)
            );
            delta.p2pSupplyAmount -= matchedDelta.rayDiv(vars.p2pSupplyIndex);
            vars.toWithdraw += matchedDelta;
            vars.remainingToWithdraw -= matchedDelta;
            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (
            vars.remainingToWithdraw > 0 &&
            !market[_poolToken].isP2PDisabled &&
            suppliersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchSuppliers(
                _poolToken,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            vars.remainingToWithdraw -= matched;
            vars.toWithdraw += matched;
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(underlyingToken, _poolToken, vars.toWithdraw); // Reverts on error.

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = _unmatchBorrowers(
                _poolToken,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );

            // Increase the peer-to-peer borrow delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).rayDiv(
                    poolIndexes[_poolToken].poolBorrowIndex
                );
                emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= Math.min(
                delta.p2pSupplyAmount,
                vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
            );
            delta.p2pBorrowAmount -= Math.min(
                delta.p2pBorrowAmount,
                unmatched.rayDiv(p2pBorrowIndex[_poolToken])
            );
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
        }

        if (inP2P == 0 && onPool == 0) _setSupplying(_supplier, borrowMask[_poolToken], false);
        underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(_supplier, _receiver, _poolToken, _amount, onPool, inP2P);
    }

    /// @dev Implements repay logic without security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _unsafeRepayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);
        Types.RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = poolIndexes[_poolToken].poolBorrowIndex;

        (uint256 inP2P, uint256 onPool) = _borrowBalanceInOf(_poolToken, _onBehalf);

        /// Pool repay ///

        // Repay borrow on pool.
        vars.borrowedOnPool = onPool;
        if (vars.borrowedOnPool > 0) {
            vars.toRepay = Math.min(
                vars.borrowedOnPool.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            onPool -= Math.min(vars.borrowedOnPool, vars.toRepay.rayDiv(vars.poolBorrowIndex)); // In adUnit.

            if (vars.remainingToRepay == 0) {
                _updateBorrowerInDS(_poolToken, _onBehalf, onPool, inP2P);
                _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

                if (inP2P == 0 && onPool == 0)
                    _setBorrowing(_onBehalf, borrowMask[_poolToken], false);

                emit Repaid(_repayer, _onBehalf, _poolToken, _amount, onPool, inP2P);

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolToken];
        vars.poolSupplyIndex = poolIndexes[_poolToken].poolSupplyIndex;
        inP2P -= Math.min(inP2P, vars.remainingToRepay.rayDiv(vars.p2pBorrowIndex)); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(_poolToken, _onBehalf, onPool, inP2P);

        // Reduce the peer-to-peer borrow delta.
        if (vars.remainingToRepay > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            ); // In underlying.

            delta.p2pBorrowDelta = delta.p2pBorrowDelta.zeroFloorSub(
                vars.remainingToRepay.rayDiv(vars.poolBorrowIndex)
            );
            delta.p2pBorrowAmount -= matchedDelta.rayDiv(vars.p2pBorrowIndex);
            vars.toRepay += matchedDelta;
            vars.remainingToRepay -= matchedDelta;
            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Repay the fee.
        if (vars.remainingToRepay > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            vars.feeToRepay = Math.zeroFloorSub(
                delta.p2pBorrowAmount.rayMul(vars.p2pBorrowIndex),
                delta.p2pSupplyAmount.rayMul(vars.p2pSupplyIndex).zeroFloorSub(
                    delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex)
                )
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = Math.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.rayDiv(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
            }
        }

        /// Transfer repay ///

        // Promote pool borrowers.
        if (
            vars.remainingToRepay > 0 &&
            !market[_poolToken].isP2PDisabled &&
            borrowersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchBorrowers(
                _poolToken,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            vars.remainingToRepay -= matched;
            vars.toRepay += matched;
        }

        _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Breaking repay ///

        // Demote peer-to-peer suppliers.
        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolToken,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );

            // Increase the peer-to-peer supply delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).rayDiv(
                    vars.poolSupplyIndex
                );
                emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            }

            // Math.min as the last decimal might flip.
            delta.p2pSupplyAmount -= Math.min(
                unmatched.rayDiv(vars.p2pSupplyIndex),
                delta.p2pSupplyAmount
            );
            delta.p2pBorrowAmount -= Math.min(
                vars.remainingToRepay.rayDiv(vars.p2pBorrowIndex),
                delta.p2pBorrowAmount
            );
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        if (inP2P == 0 && onPool == 0) _setBorrowing(_onBehalf, borrowMask[_poolToken], false);

        emit Repaid(_repayer, _onBehalf, _poolToken, _amount, onPool, inP2P);
    }

    /// @dev Returns the health factor of the user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw from.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return The health factor of the user.
    function _getUserHealthFactor(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount
    ) internal returns (uint256) {
        Types.HealthFactorVars memory vars;
        vars.userMarkets = userMarkets[_user];

        // If the user is not borrowing any asset, return an infinite health factor.
        if (!_isBorrowingAny(vars.userMarkets)) return type(uint256).max;

        Types.LiquidityData memory values = _liquidityData(_user, _poolToken, _withdrawnAmount, 0);

        return
            values.debt > 0 ? values.liquidationThreshold.wadDiv(values.debt) : type(uint256).max;
    }

    /// @dev Checks whether the user can withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return Whether the withdraw is allowed or not.
    function _withdrawAllowed(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount
    ) internal returns (bool) {
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // For safety concerns and as a withdraw on Morpho can trigger a borrow on pool, Morpho prevents withdrawals in such circumstances.
        address priceOracleSentinel = addressesProvider.getPriceOracleSentinel();
        if (
            priceOracleSentinel != address(0) &&
            !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()
        ) return false;

        return
            _getUserHealthFactor(_user, _poolToken, _withdrawnAmount) >=
            HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @dev Returns whether a given user is liquidatable and the applicable close factor, given the deprecated status of the borrowed market.
    /// @param _user The user to check.
    /// @param _isDeprecated Whether the borrowed market is deprecated or not.
    /// @return liquidationAllowed Whether the liquidation is allowed or not.
    /// @return closeFactor The close factor to apply.
    function _liquidationAllowed(address _user, bool _isDeprecated)
        internal
        returns (bool liquidationAllowed, uint256 closeFactor)
    {
        if (_isDeprecated) {
            liquidationAllowed = true;
            closeFactor = MAX_BASIS_POINTS; // Allow liquidation of the whole debt.
        } else {
            uint256 healthFactor = _getUserHealthFactor(_user, address(0), 0);
            address priceOracleSentinel = addressesProvider.getPriceOracleSentinel();

            if (priceOracleSentinel != address(0))
                liquidationAllowed = (healthFactor < MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD ||
                    (IPriceOracleSentinel(priceOracleSentinel).isLiquidationAllowed() &&
                        healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD));
            else liquidationAllowed = healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;

            if (liquidationAllowed)
                closeFactor = healthFactor > MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD
                    ? DEFAULT_LIQUIDATION_CLOSE_FACTOR
                    : MAX_LIQUIDATION_CLOSE_FACTOR;
        }
    }
}
