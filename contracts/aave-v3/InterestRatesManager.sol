// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import "./MorphoUtils.sol";

/// @title InterestRatesManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRatesManager is IInterestRatesManager, MorphoUtils {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// STRUCTS ///

    /// EXTERNAL ///

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function updateIndexes(address _poolToken) external {
        Types.PoolIndexes storage marketPoolIndexes = poolIndexes[_poolToken];

        if (block.timestamp == marketPoolIndexes.lastUpdateTimestamp) return;

        Types.Market storage market = market[_poolToken];

        address underlyingToken = market.underlyingToken;
        uint256 newPoolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        uint256 newPoolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        Types.IRMParams memory params = Types.IRMParams(
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

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params);

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
