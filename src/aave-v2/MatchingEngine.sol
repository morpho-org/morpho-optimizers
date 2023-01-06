// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./MorphoUtils.sol";

/// @title MatchingEngine.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract managing the matching engine.
abstract contract MatchingEngine is MorphoUtils {
    using HeapOrdering for HeapOrdering.HeapArray;
    using WadRayMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct UnmatchVars {
        uint256 p2pIndex;
        uint256 toUnmatch;
        uint256 poolIndex;
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        uint256 p2pIndex;
        uint256 toMatch;
        uint256 poolIndex;
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// INTERNAL ///

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
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolSupplyIndex;
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstPoolSupplier;
        uint256 remainingToMatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        while (
            remainingToMatch > 0 &&
            (firstPoolSupplier = suppliersOnPool[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            Types.SupplyBalance storage firstPoolSupplierBalance = supplyBalanceInOf[_poolToken][
                firstPoolSupplier
            ];

            uint256 poolSupplyBalance = firstPoolSupplierBalance.onPool;
            uint256 p2pSupplyBalance = firstPoolSupplierBalance.inP2P;

            vars.toMatch = Math.min(poolSupplyBalance.rayMul(vars.poolIndex), remainingToMatch);
            remainingToMatch -= vars.toMatch;

            poolSupplyBalance -= vars.toMatch.rayDiv(vars.poolIndex);
            p2pSupplyBalance += vars.toMatch.rayDiv(vars.p2pIndex);

            firstPoolSupplierBalance.onPool = poolSupplyBalance;
            firstPoolSupplierBalance.inP2P = p2pSupplyBalance;

            _updateSupplierInDS(_poolToken, firstPoolSupplier);
            emit SupplierPositionUpdated(
                firstPoolSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
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
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolSupplyIndex;
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstP2PSupplier;
        uint256 remainingToUnmatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        while (
            remainingToUnmatch > 0 &&
            (firstP2PSupplier = suppliersInP2P[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            Types.SupplyBalance storage firstP2PSupplierBalance = supplyBalanceInOf[_poolToken][
                firstP2PSupplier
            ];

            uint256 poolSupplyBalance = firstP2PSupplierBalance.onPool;
            uint256 p2pSupplyBalance = firstP2PSupplierBalance.inP2P;

            vars.toUnmatch = Math.min(p2pSupplyBalance.rayMul(vars.p2pIndex), remainingToUnmatch);
            remainingToUnmatch -= vars.toUnmatch;

            poolSupplyBalance += vars.toUnmatch.rayDiv(vars.poolIndex);
            p2pSupplyBalance -= vars.toUnmatch.rayDiv(vars.p2pIndex);

            firstP2PSupplierBalance.onPool = poolSupplyBalance;
            firstP2PSupplierBalance.inP2P = p2pSupplyBalance;

            _updateSupplierInDS(_poolToken, firstP2PSupplier);
            emit SupplierPositionUpdated(
                firstP2PSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        // Safe unchecked because _amount >= remainingToUnmatch.
        unchecked {
            unmatched = _amount - remainingToUnmatch;
        }
    }

    /// @notice Matches borrowers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects stored indexes to have been updated.
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
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstPoolBorrower;
        uint256 remainingToMatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        while (
            remainingToMatch > 0 &&
            (firstPoolBorrower = borrowersOnPool[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            Types.BorrowBalance storage firstPoolBorrowerBalance = borrowBalanceInOf[_poolToken][
                firstPoolBorrower
            ];

            uint256 poolBorrowBalance = firstPoolBorrowerBalance.onPool;
            uint256 p2pBorrowBalance = firstPoolBorrowerBalance.inP2P;

            vars.toMatch = Math.min(poolBorrowBalance.rayMul(vars.poolIndex), remainingToMatch);
            remainingToMatch -= vars.toMatch;

            poolBorrowBalance -= vars.toMatch.rayDiv(vars.poolIndex);
            p2pBorrowBalance += vars.toMatch.rayDiv(vars.p2pIndex);

            firstPoolBorrowerBalance.onPool = poolBorrowBalance;
            firstPoolBorrowerBalance.inP2P = p2pBorrowBalance;

            _updateBorrowerInDS(_poolToken, firstPoolBorrower);
            emit BorrowerPositionUpdated(
                firstPoolBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
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
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstP2PBorrower;
        uint256 remainingToUnmatch = _amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        while (
            remainingToUnmatch > 0 &&
            (firstP2PBorrower = borrowersInP2P[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            Types.BorrowBalance storage firstP2PBorrowerBalance = borrowBalanceInOf[_poolToken][
                firstP2PBorrower
            ];

            uint256 poolBorrowBalance = firstP2PBorrowerBalance.onPool;
            uint256 p2pBorrowBalance = firstP2PBorrowerBalance.inP2P;

            vars.toUnmatch = Math.min(p2pBorrowBalance.rayMul(vars.p2pIndex), remainingToUnmatch);
            remainingToUnmatch -= vars.toUnmatch;

            poolBorrowBalance += vars.toUnmatch.rayDiv(vars.poolIndex);
            p2pBorrowBalance -= vars.toUnmatch.rayDiv(vars.p2pIndex);

            firstP2PBorrowerBalance.onPool = poolBorrowBalance;
            firstP2PBorrowerBalance.inP2P = p2pBorrowBalance;

            _updateBorrowerInDS(_poolToken, firstP2PBorrower);
            emit BorrowerPositionUpdated(
                firstP2PBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        // Safe unchecked because _amount >= remainingToUnmatch.
        unchecked {
            unmatched = _amount - remainingToUnmatch;
        }
    }

    /// @notice Updates the given `_user`'s position in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function _updateSupplierInDS(address _poolToken, address _user) internal {
        Types.SupplyBalance memory supplyBalance = supplyBalanceInOf[_poolToken][_user];
        HeapOrdering.HeapArray storage marketSuppliersOnPool = suppliersOnPool[_poolToken];
        HeapOrdering.HeapArray storage marketSuppliersInP2P = suppliersInP2P[_poolToken];
        uint256 maxSortedUsersMem = maxSortedUsers;

        marketSuppliersOnPool.update(
            _user,
            marketSuppliersOnPool.getValueOf(_user),
            supplyBalance.onPool,
            maxSortedUsersMem
        );
        marketSuppliersInP2P.update(
            _user,
            marketSuppliersInP2P.getValueOf(_user),
            supplyBalance.inP2P,
            maxSortedUsersMem
        );
    }

    /// @notice Updates the given `_user`'s position in the borrower data structures.
    /// @param _poolToken The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function _updateBorrowerInDS(address _poolToken, address _user) internal {
        Types.BorrowBalance memory borrowBalance = borrowBalanceInOf[_poolToken][_user];
        HeapOrdering.HeapArray storage marketBorrowersOnPool = borrowersOnPool[_poolToken];
        HeapOrdering.HeapArray storage marketBorrowersInP2P = borrowersInP2P[_poolToken];
        uint256 maxSortedUsersMem = maxSortedUsers;

        marketBorrowersOnPool.update(
            _user,
            marketBorrowersOnPool.getValueOf(_user),
            borrowBalance.onPool,
            maxSortedUsersMem
        );
        marketBorrowersInP2P.update(
            _user,
            marketBorrowersInP2P.getValueOf(_user),
            borrowBalance.inP2P,
            maxSortedUsersMem
        );
    }
}
