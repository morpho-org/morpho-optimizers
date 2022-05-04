// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/compound/ICompound.sol";
import "./interfaces/IInterestRates.sol";
import "./interfaces/IMorpho.sol";

import "./libraries/CompoundMath.sol";

import "./MorphoStorage.sol";

/// @title InterestRates.
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRates is IInterestRates, MorphoStorage {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct Params {
        uint256 p2pSupplyIndex; // The current peer-to-peer supply index.
        uint256 p2pBorrowIndex; // The current peer-to-peer borrow index
        uint256 poolSupplyIndex; // The current pool supply index
        uint256 poolBorrowIndex; // The pool supply index at last update.
        uint256 lastPoolSupplyIndex; // The pool borrow index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The reserve factor percentage (10 000 = 100%).
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
    /// @param _newP2PSupplyIndex The new value of the supply index from peer-to-peer unit to underlying.
    /// @param _newP2PBorrowIndex The new value of the borrow index from peer-to-peer unit to underlying.
    event P2PIndexesUpdated(
        address indexed _poolTokenAddress,
        uint256 _newP2PSupplyIndex,
        uint256 _newP2PBorrowIndex
    );

    /// EXTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber)
            return p2pSupplyIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            Types.MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            Params memory params = Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                deltas[_poolTokenAddress]
            );

            return _computeP2PSupplyIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer borrow index after update.
    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber)
            return p2pBorrowIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            Types.MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            Params memory params = Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                deltas[_poolTokenAddress]
            );

            return _computeP2PBorrowIndex(params);
        }
    }

    /// @notice Updates the peer-to-peer indexes.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PIndexes(address _poolTokenAddress) external {
        if (block.timestamp > lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber) {
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

            (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = computeP2PIndexes(params);

            p2pSupplyIndex[_poolTokenAddress] = newP2PSupplyIndex;
            p2pBorrowIndex[_poolTokenAddress] = newP2PBorrowIndex;

            poolIndexes.lastUpdateBlockNumber = uint32(block.timestamp);
            poolIndexes.lastSupplyPoolIndex = uint112(poolSupplyIndex);
            poolIndexes.lastBorrowPoolIndex = uint112(poolBorrowIndex);

            emit P2PIndexesUpdated(_poolTokenAddress, newP2PSupplyIndex, newP2PBorrowIndex);
        }
    }

    /// PUBLIC ///

    /// @notice Computes and returns new peer-to-peer indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function computeP2PIndexes(Params memory _params)
        public
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

        RateParams memory supplyParams = RateParams({
            p2pIndex: _params.p2pSupplyIndex,
            poolIndex: _params.poolSupplyIndex,
            lastPoolIndex: _params.lastPoolSupplyIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.p2pSupplyAmount,
            p2pDelta: _params.delta.p2pSupplyDelta
        });
        RateParams memory borrowParams = RateParams({
            p2pIndex: _params.p2pBorrowIndex,
            poolIndex: _params.poolBorrowIndex,
            lastPoolIndex: _params.lastPoolBorrowIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.p2pBorrowAmount,
            p2pDelta: _params.delta.p2pBorrowDelta
        });

        newP2PSupplyIndex = _computeNewP2PIndex(
            supplyParams,
            p2pSupplyGrowthFactor,
            poolSupplyGrowthFactor
        );
        newP2PBorrowIndex = _computeNewP2PIndex(
            borrowParams,
            p2pBorrowGrowthFactor,
            poolBorrowGrowthFactor
        );
    }

    /// INTERNAL ///

    /// @notice Computes and return the new peer-to-peer supply index.
    /// @param _params Computation parameters.
    /// @return The updated p2pSupplyIndex.
    function _computeP2PSupplyIndex(Params memory _params) internal pure returns (uint256) {
        RateParams memory supplyParams = RateParams({
            p2pIndex: _params.p2pSupplyIndex,
            poolIndex: _params.poolSupplyIndex,
            lastPoolIndex: _params.lastPoolSupplyIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.p2pSupplyAmount,
            p2pDelta: _params.delta.p2pSupplyDelta
        });

        (uint256 p2pSupplyGrowthFactor, uint256 poolSupplyGrowthFactor, , ) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pIndexCursor
        );

        return _computeNewP2PIndex(supplyParams, p2pSupplyGrowthFactor, poolSupplyGrowthFactor);
    }

    /// @notice Computes and return the new peer-to-peer borrow index.
    /// @param _params Computation parameters.
    /// @return The updated p2pBorrowIndex.
    function _computeP2PBorrowIndex(Params memory _params) internal pure returns (uint256) {
        RateParams memory borrowParams = RateParams({
            p2pIndex: _params.p2pBorrowIndex,
            poolIndex: _params.poolBorrowIndex,
            lastPoolIndex: _params.lastPoolBorrowIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.p2pBorrowAmount,
            p2pDelta: _params.delta.p2pBorrowDelta
        });

        (, , uint256 p2pBorrowGrowthFactor, uint256 poolBorrowGrowthFactor) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pIndexCursor
        );

        return _computeNewP2PIndex(borrowParams, p2pBorrowGrowthFactor, poolBorrowGrowthFactor);
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

    /// @dev Computes and returns the new peer-to-peer index.
    /// @param _params Computation parameters.
    /// @param _p2pGrowthFactor The peer-to-peer growth factor.
    /// @param _poolGrowthFactor The pool growth factor.
    /// @return newP2PIndex The updated peer-to-peer index.
    function _computeNewP2PIndex(
        RateParams memory _params,
        uint256 _p2pGrowthFactor,
        uint256 _poolGrowthFactor
    ) internal pure returns (uint256 newP2PIndex) {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PIndex = _params.p2pIndex.mul(_p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolIndex).div(_params.p2pIndex).div(
                    _params.p2pAmount
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PIndex = _params.p2pIndex.mul(
                (WAD - shareOfTheDelta).mul(_p2pGrowthFactor) +
                    shareOfTheDelta.mul(_poolGrowthFactor)
            );
        }
    }
}
