// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/InterestRatesModel.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using CompoundMath for uint256;

    /// EXTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The virtually updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyIndex)
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        p2pSupplyIndex = indexes.p2pSupplyIndex;
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The virtually updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        external
        view
        returns (uint256 p2pBorrowIndex)
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        p2pBorrowIndex = indexes.p2pBorrowIndex;
    }

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return indexes The given market's virtually updated indexes.
    function getIndexes(address _poolToken, bool _updated)
        public
        view
        returns (Types.Indexes memory indexes)
    {
        (, indexes) = _getIndexes(_poolToken, _updated);
    }

    /// @dev Returns Compound's updated indexes of a given market.
    /// @param _poolToken The address of the market.
    /// @return The supply index.
    /// @return The borrow index.
    function getCurrentPoolIndexes(address _poolToken) public view returns (uint256, uint256) {
        return interestRatesManager.getCurrentPoolIndexes(_poolToken);
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return delta The given market's deltas.
    /// @return indexes The given market's updated indexes.
    function _getIndexes(address _poolToken, bool _updated)
        internal
        view
        returns (Types.Delta memory delta, Types.Indexes memory indexes)
    {
        (indexes, delta) = interestRatesManager.getIndexes(_poolToken, _updated);
    }
}
