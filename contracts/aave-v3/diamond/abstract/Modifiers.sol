// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {EventsAndErrors as E} from "../libraries/EventsAndErrors.sol";
import {StorageGetters} from "./StorageGetters.sol";

import {LibMarkets, LibPositions, LibDiamond} from "../libraries/Libraries.sol";

/// @title Modifiers.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice A contract to share modifiers among facets.
abstract contract Modifiers is StorageGetters {
    /// @notice Prevents updating a market not created yet.
    /// @param _poolToken The address of the market to check.
    modifier isMarketCreated(address _poolToken) {
        if (!LibMarkets.isMarketCreated(_poolToken)) revert E.MarketNotCreated();
        _;
    }

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
    }
}
