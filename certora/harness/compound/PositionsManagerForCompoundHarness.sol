// SPDX-License-Identifier: None
pragma solidity 0.8.7;

// This is the contract that is actually verified; it may contain some helper
// methods for the spec to access internal state, or may override some of the
// more complex methods in the original contract.

import "../munged/compound/PositionsManager.sol";

contract PositionsManagerHarness is PositionsManager {
    constructor(address _compoundMarketsManager, address _proxyComptrollerAddress)
        PositionsManager(_compoundMarketsManager, _proxyComptrollerAddress)
    {}

    // any helpers or modifications to existing functions go here
}
