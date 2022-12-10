// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./MorphoUtils.sol";

/// @title MatchingEngine.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract managing the matching engine.
abstract contract MatchingEngine is MorphoUtils {
    using HeapOrdering for HeapOrdering.HeapArray;
    using HeapOrdering2 for HeapOrdering.HeapArray;
    using WadRayMath for uint256;

    /// STRUCTS ///

    struct MatchVars {
        address poolToken;
        uint256 poolIndex;
        uint256 p2pIndex;
        uint256 amount;
        uint256 maxGasForMatching;
        bool borrow;
        bool matching; // True for match, False for unmatch
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event PositionUpdated(
        bool _borrow,
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
        return
            _match(
                suppliersOnPool[_poolToken],
                suppliersInP2P[_poolToken],
                _matchStep,
                MatchVars(
                    _poolToken,
                    poolIndexes[_poolToken].poolSupplyIndex,
                    p2pSupplyIndex[_poolToken],
                    _amount,
                    _maxGasForMatching,
                    false,
                    true
                )
            );
    }

    /// @notice Matches borrowers' liquidity waiting on Aave up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects stored indexes to have been updated
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
        return
            _match(
                borrowersOnPool[_poolToken],
                borrowersInP2P[_poolToken],
                _matchStep,
                MatchVars(
                    _poolToken,
                    poolIndexes[_poolToken].poolBorrowIndex,
                    p2pBorrowIndex[_poolToken],
                    _amount,
                    _maxGasForMatching,
                    true,
                    true
                )
            );
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
        (unmatched, ) = _match(
            suppliersOnPool[_poolToken],
            suppliersInP2P[_poolToken],
            _unmatchStep,
            MatchVars(
                _poolToken,
                poolIndexes[_poolToken].poolSupplyIndex,
                p2pSupplyIndex[_poolToken],
                _amount,
                _maxGasForMatching,
                false,
                false
            )
        );
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
        (unmatched, ) = _match(
            borrowersOnPool[_poolToken],
            borrowersInP2P[_poolToken],
            _unmatchStep,
            MatchVars(
                _poolToken,
                poolIndexes[_poolToken].poolBorrowIndex,
                p2pBorrowIndex[_poolToken],
                _amount,
                _maxGasForMatching,
                true,
                false
            )
        );
    }

    function _match(
        HeapOrdering.HeapArray storage _heapOnPool,
        HeapOrdering.HeapArray storage _heapInP2P,
        function(uint256, uint256, uint256, uint256, uint256)
            pure
            returns (uint256, uint256, uint256) _f,
        MatchVars memory vars
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (vars.maxGasForMatching == 0) return (0, 0);

        address firstUser;
        uint256 remainingToMatch = vars.amount;
        uint256 gasLeftAtTheBeginning = gasleft();

        while (
            remainingToMatch > 0 &&
            (firstUser = vars.matching ? _heapOnPool.getHead() : _heapInP2P.getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (gasLeftAtTheBeginning - gasleft() >= vars.maxGasForMatching) break;
            }
            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remainingToMatch) = _f(
                _heapOnPool.getValueOf(firstUser),
                _heapInP2P.getValueOf(firstUser),
                vars.poolIndex,
                vars.p2pIndex,
                remainingToMatch
            );

            if (!vars.borrow) _updateSupplierInDS(vars.poolToken, firstUser, onPool, inP2P);
            else _updateBorrowerInDS(vars.poolToken, firstUser, onPool, inP2P);

            emit PositionUpdated(vars.borrow, firstUser, vars.poolToken, onPool, inP2P);
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = vars.amount - remainingToMatch;
            gasConsumedInMatching = gasLeftAtTheBeginning - gasleft();
        }
    }

    function _matchStep(
        uint256 _poolBalance,
        uint256 _p2pBalance,
        uint256 _poolIndex,
        uint256 _p2pIndex,
        uint256 _remaining
    )
        internal
        pure
        returns (
            uint256 newPoolBalance,
            uint256 newP2PBalance,
            uint256 remaining
        )
    {
        uint256 toProcess = Math.min(_poolBalance.rayMul(_poolIndex), _remaining);
        remaining = _remaining - toProcess;
        newPoolBalance = _poolBalance - toProcess.rayDiv(_poolIndex);
        newP2PBalance = _p2pBalance + toProcess.rayDiv(_p2pIndex);
    }

    function _unmatchStep(
        uint256 _poolBalance,
        uint256 _p2pBalance,
        uint256 _poolIndex,
        uint256 _p2pIndex,
        uint256 _remaining
    )
        internal
        pure
        returns (
            uint256 newPoolBalance,
            uint256 newP2PBalance,
            uint256 remaining
        )
    {
        uint256 toProcess = Math.min(_p2pBalance.rayMul(_p2pIndex), _remaining);
        remaining = _remaining - toProcess;
        newPoolBalance = _poolBalance + toProcess.rayDiv(_poolIndex);
        newP2PBalance = _p2pBalance - toProcess.rayDiv(_p2pIndex);
    }

    /// @param _token The market to update.
    /// @param _user The user.
    /// @param _marketOnPool The data structure of the pool market. Pass in the supplier or borrower pool heap.
    /// @param _marketInP2P The data structure of the P2P market. Pass in the supplier or borrower P2P heap.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateInDS(
        address _token,
        address _user,
        HeapOrdering.HeapArray storage _marketOnPool,
        HeapOrdering.HeapArray storage _marketInP2P,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        uint256 formerOnPool = _marketOnPool.getValueOf(_user);

        if (onPool != formerOnPool) {
            if (address(rewardsManager) != address(0))
                rewardsManager.updateUserAssetAndAccruedRewards(
                    rewardsController,
                    _user,
                    _token,
                    formerOnPool,
                    IScaledBalanceToken(_token).scaledTotalSupply()
                );
            _marketOnPool.update(_user, onPool, maxSortedUsers);
        }
        _marketInP2P.update(_user, inP2P, maxSortedUsers);
    }

    /// @notice Updates the given `_user`'s position in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateSupplierInDS(
        address _poolToken,
        address _user,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        _updateInDS(
            _poolToken,
            _user,
            suppliersOnPool[_poolToken],
            suppliersInP2P[_poolToken],
            onPool,
            inP2P
        );
    }

    /// @notice Updates the given `_user`'s position in the borrower data structures.
    /// @param _poolToken The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    /// @param onPool The new on pool value.
    /// @param inP2P The new in P2P value.
    function _updateBorrowerInDS(
        address _poolToken,
        address _user,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        address variableDebtTokenAddress = pool
        .getReserveData(market[_poolToken].underlyingToken)
        .variableDebtTokenAddress;

        _updateInDS(
            variableDebtTokenAddress,
            _user,
            borrowersOnPool[_poolToken],
            borrowersInP2P[_poolToken],
            onPool,
            inP2P
        );
    }
}
