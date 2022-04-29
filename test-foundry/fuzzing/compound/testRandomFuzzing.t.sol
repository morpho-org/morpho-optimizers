// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestRandomFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testRandomFuzzed(
        uint128 _amount,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        bool _doBorrow,
        bool _doRepay,
        bool _doWithdraw
    ) public {
        hevm.assume(_amount > 0 && amount <= ERC20(underlying).balanceOf(address(supplier1)));

        performSupply(supplier1, _amount, _suppliedAsset);

        if (_doBorrow) {
            (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
                address(supplier1),
                borrowedAsset
            );
            performBorrow(supplier1, _amount, _borrowedAsset);
        }
    }
}
