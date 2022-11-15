// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";
import {Types, Math, ERC20, EventsAndErrors as E} from "./Libraries.sol";
import {IAToken, IVariableDebtToken} from "../interfaces/Interfaces.sol";
import {LibIndexes} from "./LibIndexes.sol";
import {LibMarkets} from "./LibMarkets.sol";
import {LibUsers} from "./LibUsers.sol";

library LibPositions {
    function c() internal pure returns (S.ContractsLayout storage c) {
        c = S.contractsLayout();
    }

    function m() internal pure returns (S.MarketsLayout storage m) {
        m = S.marketsLayout();
    }

    function p() internal pure returns (S.PositionsLayout storage p) {
        p = S.positionsLayout();
    }

    struct SupplyVars {
        uint256 remainingToSupply;
        uint256 poolBorrowIndex;
        uint256 toRepay;
    }

    function supply(
        address _poolToken,
        address _from,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        SupplyVars memory vars;

        Types.Market memory market = m().market[_poolToken];
        Types.Delta storage delta = m().deltas[_poolToken];
        ERC20 underlyingToken = ERC20(market.underlyingToken);

        validateSupply(market, _from, _onBehalf, _amount);
        LibIndexes.updateIndexes(_poolToken);
        LibUsers.setSupplying(_onBehalf, p().borrowMask[_poolToken], true);

        underlyingToken.safeTransferFrom(_from, address(this), _amount);

        vars.poolBorrowIndex = m().poolIndexes[_poolToken].poolBorrowIndex;
        vars.remainingToSupply = _amount;
    }

    function supplyP2P(Types.Delta storage delta, SupplyVars memory vars)
        internal
        view
        returns (SupplyVars memory)
    {
        if (delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToSupply
            ); // In underlying.

            delta.p2pBorrowDelta = delta.p2pBorrowDelta.zeroFloorSub(
                vars.remainingToSupply.rayDiv(vars.poolBorrowIndex)
            );
            vars.toRepay += matchedDelta;
            vars.remainingToSupply -= matchedDelta;
            emit E.P2PBorrowDeltaUpdated(address(0), delta.p2pBorrowDelta);
        }
        return vars;
    }

    function matchP2PBorrowDelta(Types.Delta storage delta, SupplyVars memory vars)
        internal
        view
        returns (SupplyVars memory)
    {
        if (delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToSupply
            ); // In underlying.

            delta.p2pBorrowDelta = delta.p2pBorrowDelta.zeroFloorSub(
                vars.remainingToSupply.rayDiv(vars.poolBorrowIndex)
            );
            vars.toRepay += matchedDelta;
            vars.remainingToSupply -= matchedDelta;
            emit E.P2PBorrowDeltaUpdated(address(0), delta.p2pBorrowDelta);
        }
        return vars;
    }

    function promotePoolBorrowers(SupplyVars memory vars, Types.Market memory market)
        internal
        view
    {}

    function validateSupply(
        Types.Market memory _market,
        address _from,
        address _onBehalf,
        uint256 _amount
    ) internal view returns (bool) {
        if (_onBehalf == address(0)) revert E.AddressIsZero();
        if (_amount == 0) revert E.AmountIsZero();
        if (LibMarkets.isMarketCreated(_market)) revert E.MarketNotCreated();
        if (_market.isSupplyPaused) revert E.SupplyIsPaused();
    }

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        c().pool.supply(address(_underlyingToken), _amount, address(this), S.NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _poolToken The address of the market.
    /// @param _amount The amount of token (in underlying).
    function withdrawFromPool(
        ERC20 _underlyingToken,
        address _poolToken,
        uint256 _amount
    ) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        _amount = Math.min(IAToken(_poolToken).balanceOf(address(this)), _amount);
        c().pool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function borrowFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        c().pool.borrow(
            address(_underlyingToken),
            _amount,
            S.VARIABLE_INTEREST_MODE,
            S.NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function repayToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        if (
            _amount == 0 ||
            IVariableDebtToken(
                c().pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this)) ==
            0
        ) return;

        c().pool.repay(address(_underlyingToken), _amount, S.VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }
}
