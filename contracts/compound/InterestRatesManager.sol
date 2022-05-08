// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IInterestRatesManager.sol";
import "./interfaces/IMorpho.sol";

import "./libraries/CompoundMath.sol";

import "./MorphoStorage.sol";

/// @title InterestRatesManager.
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRatesManager is IInterestRatesManager, MorphoStorage {
    using CompoundMath for uint256;

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

    struct RateParams {
        uint256 p2pIndex; // The peer-to-peer index.
        uint256 poolIndex; // The pool index.
        uint256 lastPoolIndex; // The pool index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pAmount; // Sum of all stored peer-to-peer balance in supply or borrow (in peer-to-peer unit).
        uint256 p2pDelta; // Peer-to-peer delta in supply or borrow (in peer-to-peer unit).
    }

    /// EVENTS ///

    /// @notice Emitted when the peer-to-peer indexes of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _p2pSupplyIndex The updated supply index from peer-to-peer unit to underlying.
    /// @param _p2pBorrowIndex The updated borrow index from peer-to-peer unit to underlying.
    /// @param _poolSupplyIndex The updated pool supply index.
    /// @param _poolBorrowIndex The updated pool borrow index.
    event P2PIndexesUpdated(
        address indexed _poolTokenAddress,
        uint256 _p2pSupplyIndex,
        uint256 _p2pBorrowIndex,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex
    );

    /// EXTERNAL ///

    /// @notice Updates the peer-to-peer indexes.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PIndexes(address _poolTokenAddress) external {
        if (block.number > lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            Types.MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            uint256 poolSupplyIndex = poolToken.exchangeRateCurrent();
            uint256 poolBorrowIndex = poolToken.borrowIndex();

            Params memory params = Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                deltas[_poolTokenAddress]
            );

            (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params);

            p2pSupplyIndex[_poolTokenAddress] = newP2PSupplyIndex;
            p2pBorrowIndex[_poolTokenAddress] = newP2PBorrowIndex;

            poolIndexes.lastUpdateBlockNumber = uint32(block.number);
            poolIndexes.lastSupplyPoolIndex = uint112(poolSupplyIndex);
            poolIndexes.lastBorrowPoolIndex = uint112(poolBorrowIndex);

            emit P2PIndexesUpdated(
                _poolTokenAddress,
                newP2PSupplyIndex,
                newP2PBorrowIndex,
                poolSupplyIndex,
                poolBorrowIndex
            );
        }
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

    /// @dev Computes and returns peer-to-peer supply growth factor and peer-to-peer borrow growth factor.
    /// @param _poolSupplyIndex The current pool supply index.
    /// @param _poolBorrowIndex The current pool borrow index.
    /// @param _lastPoolSupplyIndex The pool supply index at last update.
    /// @param _lastPoolBorrowIndex The pool borrow index at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return p2pSupplyGrowthFactor_ The peer-to-peer supply growth factor.
    /// @return poolSupplyGrowthFactor_ The supply pool growth factor.
    /// @return p2pBorrowGrowthFactor_ The peer-to-peer borrow growth factor.
    /// @return poolBorrowGrowthFactor_ The borrow pool growth factor.
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
        poolSupplyGrowthFactor_ = _poolSupplyIndex.div(_lastPoolSupplyIndex);
        poolBorrowGrowthFactor_ = _poolBorrowIndex.div(_lastPoolBorrowIndex);
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
}
