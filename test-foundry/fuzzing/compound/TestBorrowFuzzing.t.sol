// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../../compound/setup/TestSetup.sol";
import "@contracts/compound/positions-manager-parts/PositionsManagerEventsErrors.sol";

contract TestBorrow is TestSetup {
    using FixedPointMathLib for uint256;
    using CompoundMath for uint256;

    uint256 private MAX_BORROWABLE_DAI = uint256(7052532865252195763) / 2; // approx, taken from market conditions

    function testBorrow1Fuzzed(uint256 supplied, uint256 borrowed) public {
        hevm.assume(
            supplied != 0 && supplied < INITIAL_BALANCE * 1e6 && borrowed != 0 && borrowed < 1e50
        );

        borrower1.approve(usdc, supplied);
        borrower1.supply(cUsdc, supplied);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        hevm.assume(borrowed > borrowable);
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(cDai, borrowed);
    }

    // sould borrow an authorized amount of dai after having provided some usdc
    function testBorrowFuzzed(uint256 amountSupplied, uint256 amountBorrowed) public {
        console.log(ERC20(usdc).balanceOf(address(borrower1)));

        hevm.assume(
            amountSupplied != 0 && amountSupplied < INITIAL_BALANCE * 1e6 && amountBorrowed != 0
        );

        borrower1.approve(usdc, amountSupplied);
        borrower1.supply(cUsdc, amountSupplied);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );
        hevm.assume(amountBorrowed <= borrowable && amountBorrowed <= MAX_BORROWABLE_DAI);

        borrower1.borrow(cDai, amountBorrowed);
    }
}
