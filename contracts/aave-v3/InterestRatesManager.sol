// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import "./libraries/Math.sol";

import "./MorphoStorage.sol";

/// @title InterestRatesManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRatesManager is IInterestRatesManager, MorphoStorage {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

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

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolTokenAddress The address of the market to update.
    function updateIndexes(address _poolTokenAddress) external {
        if (block.timestamp > poolIndexes[_poolTokenAddress].lastUpdateTimestamp) {
            Types.PoolIndexes storage poolIndexes = poolIndexes[_poolTokenAddress];
            Types.MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
            uint256 newPoolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
            uint256 newPoolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

            Params memory params = Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                poolIndexes.poolSupplyIndex,
                poolIndexes.poolBorrowIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                deltas[_poolTokenAddress]
            );

            (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params);

            p2pSupplyIndex[_poolTokenAddress] = newP2PSupplyIndex;
            p2pBorrowIndex[_poolTokenAddress] = newP2PBorrowIndex;

            poolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
            poolIndexes.poolSupplyIndex = uint112(newPoolSupplyIndex);
            poolIndexes.poolBorrowIndex = uint112(newPoolBorrowIndex);

            emit P2PIndexesUpdated(
                _poolTokenAddress,
                newP2PSupplyIndex,
                newP2PBorrowIndex,
                newPoolSupplyIndex,
                newPoolBorrowIndex
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
        // Compute pool growth factors

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.rayDiv(
            _params.lastPoolSupplyIndex
        );
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.rayDiv(
            _params.lastPoolBorrowIndex
        );

        // Compute peer-to-peer growth factors

        uint256 p2pGrowthFactor = poolSupplyGrowthFactor.percentMul(
            MAX_BASIS_POINTS - _params.p2pIndexCursor
        ) + poolBorrowGrowthFactor.percentMul(_params.p2pIndexCursor);
        uint256 p2pSupplyGrowthFactor = p2pGrowthFactor -
            _params.reserveFactor.percentMul(p2pGrowthFactor - poolSupplyGrowthFactor);
        uint256 p2pBorrowGrowthFactor = p2pGrowthFactor +
            _params.reserveFactor.percentMul(poolBorrowGrowthFactor - p2pGrowthFactor);

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
                (_params.delta.p2pBorrowDelta.wadToRay().rayMul(_params.lastPoolBorrowIndex))
                .rayDiv(
                    (_params.delta.p2pBorrowAmount.wadToRay()).rayMul(_params.lastP2PBorrowIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.rayMul(poolBorrowGrowthFactor)
            );
        }
    }
}
