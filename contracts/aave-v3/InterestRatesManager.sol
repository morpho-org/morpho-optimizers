// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "./libraries/InterestRatesModel.sol";

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import "./MorphoStorage.sol";

/// @title InterestRatesManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRatesManager is IInterestRatesManager, MorphoStorage {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when the peer-to-peer indexes of a market are updated.
    /// @param _poolToken The address of the market updated.
    /// @param _p2pSupplyIndex The updated supply index from peer-to-peer unit to underlying.
    /// @param _p2pBorrowIndex The updated borrow index from peer-to-peer unit to underlying.
    /// @param _poolSupplyIndex The updated pool supply index.
    /// @param _poolBorrowIndex The updated pool borrow index.
    event P2PIndexesUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyIndex,
        uint256 _p2pBorrowIndex,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex
    );

    /// EXTERNAL ///

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function updateIndexes(address _poolToken) external {
        Types.PoolIndexes storage marketPoolIndexes = poolIndexes[_poolToken];

        if (block.timestamp == marketPoolIndexes.lastUpdateTimestamp) return;

        Types.Market storage market = market[_poolToken];

        address underlyingToken = market.underlyingToken;
        (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = InterestRatesModel
        .getPoolIndexes(pool, underlyingToken);

        Types.P2PIndexComputeParams memory params = Types.P2PIndexComputeParams(
            p2pSupplyIndex[_poolToken],
            p2pBorrowIndex[_poolToken],
            newPoolSupplyIndex,
            newPoolBorrowIndex,
            marketPoolIndexes.poolSupplyIndex,
            marketPoolIndexes.poolBorrowIndex,
            market.reserveFactor,
            market.p2pIndexCursor,
            deltas[_poolToken]
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = InterestRatesModel
        .computeP2PIndexes(params);

        p2pSupplyIndex[_poolToken] = newP2PSupplyIndex;
        p2pBorrowIndex[_poolToken] = newP2PBorrowIndex;

        marketPoolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
        marketPoolIndexes.poolSupplyIndex = uint112(newPoolSupplyIndex);
        marketPoolIndexes.poolBorrowIndex = uint112(newPoolBorrowIndex);

        emit P2PIndexesUpdated(
            _poolToken,
            newP2PSupplyIndex,
            newP2PBorrowIndex,
            newPoolSupplyIndex,
            newPoolBorrowIndex
        );
    }
}
