// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IAToken.sol";
import "./interfaces/lido/ILido.sol";

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

    /// STORAGE ///

    address public constant ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    uint256 public immutable ST_ETH_BASE_REBASE_INDEX;

    constructor() {
        ST_ETH_BASE_REBASE_INDEX = ILido(ST_ETH).getPooledEthByShares(WadRayMath.RAY);
    }

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
        .getPoolIndexes(
            pool,
            underlyingToken,
            underlyingToken == ST_ETH ? ST_ETH_BASE_REBASE_INDEX : 0
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = InterestRatesModel
        .computeP2PIndexes(
            Types.P2PIndexComputeParams({
                lastP2PSupplyIndex: p2pSupplyIndex[_poolToken],
                lastP2PBorrowIndex: p2pBorrowIndex[_poolToken],
                poolSupplyIndex: newPoolSupplyIndex,
                poolBorrowIndex: newPoolBorrowIndex,
                lastPoolSupplyIndex: marketPoolIndexes.poolSupplyIndex,
                lastPoolBorrowIndex: marketPoolIndexes.poolBorrowIndex,
                reserveFactor: market.reserveFactor,
                p2pIndexCursor: market.p2pIndexCursor,
                delta: deltas[_poolToken]
            })
        );

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
