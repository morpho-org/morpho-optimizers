// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

import "../libraries/Types.sol";

interface IInterestRatesManager {
    function updateP2PIndexes(address _marketAddress) external;

    function getIndexes(address _poolToken, bool _updated)
        external
        view
        returns (Types.Indexes memory indexes, Types.Delta memory delta);

    function getCurrentPoolIndexes(address _poolToken)
        external
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex);
}
