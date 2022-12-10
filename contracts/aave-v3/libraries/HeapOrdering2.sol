// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@morpho-dao/morpho-data-structures/HeapOrdering.sol";

// Only exists for a POC
library HeapOrdering2 {
    function update(
        HeapOrdering.HeapArray storage _heap,
        address _id,
        uint256 _newValue,
        uint256 _maxSortedUsers
    ) internal {
        HeapOrdering.update(
            _heap,
            _id,
            HeapOrdering.getValueOf(_heap, _id),
            _newValue,
            _maxSortedUsers
        );
    }
}
