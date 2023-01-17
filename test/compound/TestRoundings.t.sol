// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRounding is TestSetup {
    using SafeTransferLib for ERC20;

    // This test compares balances stored by Compound & amount passed in argument.
    // The back & forth to cUnits leads to loss of information (when the underlying has enough decimals).
    function testRoundingError1() public {
        uint256 amountSupplied = 1e18;

        // Supplier1 supplies 1 Dai.
        supplier1.approve(dai, amountSupplied);
        supplier1.supply(cDai, amountSupplied);

        // Compare balances in underlying units.
        uint256 balanceOnCompInUnderlying = ICToken(cDai).balanceOfUnderlying(address(morpho));
        assertFalse(balanceOnCompInUnderlying == amountSupplied, "comparison in underlying units");

        // Previous test returns the following
        /*
        Logs:
        Error: comparison in underlying units
        Error: a == b not satisfied [uint]
            Expected: 1000000000000000000
            Actual: 999999999988707085
        */
    }

    // This test shows that small balances are discarded if amount is inferior to 1e8
    // (given enough decimals on the underlying) due to the division & multiplication with the index.
    function testRoundingError2() public {
        uint256 amountSupplied = 1e5;

        // Supplier1 supplies 1 Dai.
        supplier1.approve(dai, amountSupplied);
        supplier1.supply(cDai, amountSupplied);

        // Compare balances in underlying units.
        uint256 balanceOnCompInUnderlying = ICToken(cDai).balanceOfUnderlying(address(morpho));
        assertFalse(balanceOnCompInUnderlying == amountSupplied, "comparison in underlying units");

        // Previous test returns the following
        /*
        Logs:
        Error: comparison in underlying units
        Error: a == b not satisfied [uint]
            Expected: 100000
            Actual: 0
        */
    }

    // Calling compound function with 0 as parameter doesn't generate an error, function isn't executed.
    // However, some underlying amounts can turn out to be null when expressed in cToken units (see testRoundingError2).
    // Still, the function is executed. mint, borrow, repayBorrow are fine, but redeemUnderlying reverts.
    function testRoundingError3() public {
        deal(dai, address(this), 1e20);
        ERC20(dai).safeApprove(cDai, type(uint64).max);

        // mint 1 cDai, doesn't revert
        ICToken(cDai).mint(1);

        // borrow 1 cDai, doesn't revert
        ICToken(cDai).mint(1e18);
        ICToken(cDai).borrow(1);

        // repay 1 cDai, doesn't revert
        ICToken(cDai).repayBorrow(1);

        // redeem 1 cDai, it DOES revert
        hevm.expectRevert("redeemTokens zero");
        ICToken(cDai).redeemUnderlying(1);

        // Previous test returns the following
        /*
        [31m[FAIL. Reason: redeemTokens zero][0m testRoundingError3() (gas: 742070)
        */
    }
}
