// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../../../contracts/compound/libraries/LibStorage.sol";
import "../../../contracts/compound/libraries/Types.sol";

/// @title MarketsManagerForCompound.
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForCompound contract, an other contract interacting with Compound or a fork of Compound.
contract DummyFacet is WithStorageAndModifiers {
    function returnTrue() external pure returns (bool) {
        return true;
    }
}
