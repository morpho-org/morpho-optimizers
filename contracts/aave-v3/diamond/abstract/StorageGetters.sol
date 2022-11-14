// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";

/// @title StorageGetters.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice An inherited contract by facets to have convenient getters.
abstract contract StorageGetters {
    function g() internal pure returns (MorphoStorage.GlobalLayout storage g) {
        g = S.globalLayout();
    }

    function c() internal pure returns (MorphoStorage.ContractsLayout storage c) {
        c = S.contractsLayout();
    }

    function p() internal pure returns (MorphoStorage.PositionsLayout storage p) {
        p = S.positionsLayout();
    }

    function m() internal pure returns (MorphoStorage.MarketsLayout storage m) {
        m = S.marketsLayout();
    }
}
