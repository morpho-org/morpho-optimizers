// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/Types.sol";

interface IInterestRates {
    function computeP2PIndexes(Types.Params memory _params)
        external
        pure
        returns (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex);

    function computeSupplyP2PIndex(Types.Params memory _params) external view returns (uint256);

    function computeBorrowP2PIndex(Types.Params memory _params) external view returns (uint256);
}
