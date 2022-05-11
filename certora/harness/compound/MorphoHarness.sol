// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

// This is the contract that is actually verified; it may contain some helper
// methods for the spec to access internal state, or may override some of the
// more complex methods in the original contract.

import "../../munged/compound/Morpho.sol";

contract MorphoHarness is Morpho {
    constructor(
        IPositionsManager _positionsManager,
        IInterestRatesManager _interestRatesManager,
        IComptroller _comptroller,
        Types.MaxGasForMatching memory _defaultMaxGasForMatching,
        uint256 _dustThreshold,
        uint256 _maxSortedUsers,
        address _cEth,
        address _wEth
    ) Morpho() {
        initialize(
            _positionsManager,
            _interestRatesManager,
            _comptroller,
            _defaultMaxGasForMatching,
            _dustThreshold,
            _maxSortedUsers,
            _cEth,
            _wEth
        );
    }
}
