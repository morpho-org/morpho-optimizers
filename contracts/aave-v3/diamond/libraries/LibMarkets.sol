// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";
import {EventsAndErrors as E, Types, Math, WadRayMath, ERC20} from "./Libraries.sol";
import {LibIndexes} from "./LibIndexes.sol";
import {LibPositions} from "./LibPositions.sol";

library LibMarkets {
    using WadRayMath for uint256;
    using Math for uint256;

    function m() internal pure returns (S.MarketsLayout storage m) {
        return S.marketsLayout();
    }

    function isMarketCreated(Types.Market memory _market) internal pure returns (bool) {
        return _market.underlyingToken != address(0);
    }

    /// @notice Sets all pause statuses for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setPauseStatus(address _poolToken, bool _isPaused) internal {
        Types.Market storage market = m().market[_poolToken];

        market.isSupplyPaused = _isPaused;
        market.isBorrowPaused = _isPaused;
        market.isWithdrawPaused = _isPaused;
        market.isRepayPaused = _isPaused;
        market.isLiquidateCollateralPaused = _isPaused;
        market.isLiquidateBorrowPaused = _isPaused;

        emit E.IsSupplyPausedSet(_poolToken, _isPaused);
        emit E.IsBorrowPausedSet(_poolToken, _isPaused);
        emit E.IsWithdrawPausedSet(_poolToken, _isPaused);
        emit E.IsRepayPausedSet(_poolToken, _isPaused);
        emit E.IsLiquidateCollateralPausedSet(_poolToken, _isPaused);
        emit E.IsLiquidateBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Implements increaseP2PDeltas logic.
    /// @dev The current Morpho supply on the pool might not be enough to borrow `_amount` before resupplying it.
    /// In this case, consider calling this function multiple times.
    /// @param _poolToken The address of the market on which to increase deltas.
    /// @param _amount The maximum amount to add to the deltas (in underlying).
    function increaseP2PDeltasLogic(address _poolToken, uint256 _amount) internal {
        Types.Delta storage deltas = m().deltas[_poolToken];
        Types.PoolIndexes memory poolIndexes = m().poolIndexes[_poolToken];

        _amount = Math.min(
            _amount,
            Math.min(
                deltas.p2pSupplyAmount.rayMul(m().p2pSupplyIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pSupplyDelta.rayMul(poolIndexes.poolSupplyIndex)
                ),
                deltas.p2pBorrowAmount.rayMul(m().p2pBorrowIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pBorrowDelta.rayMul(poolIndexes.poolBorrowIndex)
                )
            )
        );

        deltas.p2pSupplyDelta += _amount.rayDiv(poolIndexes.poolSupplyIndex);
        deltas.p2pSupplyDelta = deltas.p2pSupplyDelta;
        deltas.p2pBorrowDelta += _amount.rayDiv(poolIndexes.poolBorrowIndex);
        deltas.p2pBorrowDelta = deltas.p2pBorrowDelta;
        emit E.P2PSupplyDeltaUpdated(_poolToken, deltas.p2pSupplyDelta);
        emit E.P2PBorrowDeltaUpdated(_poolToken, deltas.p2pBorrowDelta);

        ERC20 underlyingToken = ERC20(m().market[_poolToken].underlyingToken);
        LibPositions.borrowFromPool(underlyingToken, _amount);
        LibPositions.supplyToPool(underlyingToken, _amount);

        emit E.P2PDeltasIncreased(_poolToken, _amount);
    }
}
