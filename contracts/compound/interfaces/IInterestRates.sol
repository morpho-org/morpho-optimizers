// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/Types.sol";

interface IInterestRates {
    function computeP2PIndexes(Types.Params memory _params)
        external
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex);

    function computeP2PSupplyIndex(Types.Params memory _params) external view returns (uint256);

    function computeP2PBorrowIndex(Types.Params memory _params) external view returns (uint256);
}
