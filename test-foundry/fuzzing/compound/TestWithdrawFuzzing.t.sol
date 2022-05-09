// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";
import {Attacker} from "../../compound/helpers/Attacker.sol";

contract TestWithdraw is TestSetupFuzzing {
    using CompoundMath for uint256;

    /// @dev Amounts can round to zero with amounts < 1e14
    function testWithdraw1(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        borrower1.borrow(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        borrower1.withdraw(cUsdc, to6Decimals(collateral));
    }

    function testWithdraw2(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(2 * amount).div(ICToken(cUsdc).exchangeRateCurrent());

        supplier1.withdraw(cUsdc, to6Decimals(amount));
    }

    function testWithdrawAll(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        supplier1.withdraw(cUsdc, type(uint256).max);
    }

    function testWithdraw3_1(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);

        uint256 borrowedAmount = amount;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(cDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);
    }

    function testWithdraw3_2(uint256 amount, uint8 nmax) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);
        hevm.assume(nmax > 1 && nmax < 50);

        uint256 borrowedAmount = amount;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        createSigners(nmax);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (nmax - 1);

        for (uint256 i = 0; i < nmax; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier1 withdraws suppliedAmount.
        supplier1.withdraw(cDai, type(uint256).max);
    }

    function testWithdraw3_3(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);

        uint256 borrowedAmount = amount;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Supplier1 withdraws 75% of supplied amount
        uint256 toWithdraw = (75 * suppliedAmount) / 100;
        supplier1.withdraw(cDai, toWithdraw);
    }

    function testWithdraw3_4(uint256 amount, uint8 nmax) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000);
        hevm.assume(nmax > 10 && nmax < 50);

        uint256 borrowedAmount = amount;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint8 NMAX = nmax;
        createSigners(nmax);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (nmax - 1));
        uint256[] memory rates = new uint256[](NMAX);

        uint256 matchedAmount;
        for (uint256 i = 0; i < nmax; i++) {
            if (suppliers[i] == supplier1) continue;

            rates[i] = ICToken(cDai).exchangeRateCurrent();

            matchedAmount += getBalanceOnCompound(
                amountPerSupplier,
                ICToken(cDai).exchangeRateCurrent()
            );

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount.
        supplier1.withdraw(cDai, suppliedAmount);
    }

    struct Vars {
        uint256 LR;
        uint256 BPY;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    function testDeltaWithdraw(
        uint96 _amount,
        uint8 maxGas,
        uint8 numSigners
    ) public {
        hevm.assume(_amount > 1e14 && _amount < 1e18 * 50_000_000);
        hevm.assume(maxGas < 100);
        hevm.assume(numSigners > 1 && numSigners < 50);

        uint256 amount = _amount;

        // 2e6 allows only 10 unmatch borrowers.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, uint64(1e6 + maxGas * 1e5), 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = numSigners * borrowedAmount + 7;
        uint256 expectedSupplyBalanceInP2P;

        // supplier1 and 20 borrowers are matched for suppliedAmount.
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        createSigners(numSigners);
        uint256 matched;

        // 2 * NMAX borrowers borrow borrowedAmount.
        for (uint256 i; i < numSigners; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, borrowedAmount, type(uint64).max);
            matched += borrowedAmount.div(morpho.p2pBorrowIndex(cDai));
        }

        {
            // Supplier withdraws max.
            // Should create a delta on borrowers side.
            supplier1.withdraw(cDai, type(uint256).max);

            // supplier should be able to deposit to help remove delta
            supplier2.approve(dai, suppliedAmount);
            supplier2.supply(cDai, suppliedAmount);
        }

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = numSigners / 2; i < numSigners; i++) {
            borrowers[i].approve(dai, borrowedAmount);
            borrowers[i].repay(cDai, borrowedAmount);
        }
    }

    function testShouldNotWithdrawWhenUnderCollaterized(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 toSupply = amount;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // supplier2 deposits collateral.
        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        // supplier1 tries to withdraw more than allowed.
        supplier1.borrow(cUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        supplier1.withdraw(cDai, toSupply);
    }

    // Test attack.
    // Should be possible to withdraw amount while an attacker sends cToken to trick Morpho contract.
    function testWithdrawWhileAttackerSendsCToken(uint256 amount) public {
        hevm.assume(amount > 1e14 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        Attacker attacker = new Attacker();
        tip(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = amount;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // Attacker sends cToken to morpho contract.
        attacker.approve(dai, cDai, toSupply);
        attacker.deposit(cDai, toSupply);
        attacker.transfer(dai, address(morpho), toSupply);

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // borrower1 deposits collateral.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw.
        borrower1.borrow(cDai, toBorrow);
        supplier1.withdraw(cDai, toSupply);
    }

    function testWithdrawMultipleAssets(
        uint8 _proportionBorrowed,
        uint8 _suppliedAsset1,
        uint8 _suppliedAsset2,
        uint128 _amount1,
        uint128 _amount2
    ) public {
        (address asset1, address underlying1) = getAsset(_suppliedAsset1);
        (address asset2, address underlying2) = getAsset(_suppliedAsset2);

        hevm.assume(
            _amount1 >= 1e14 && _amount1 < ERC20(underlying1).balanceOf(address(asset1)) // Less than the available liquidity of CTokens, but more than would be rounded to zero
        );
        hevm.assume(_amount2 >= 1e14 && _amount2 < ERC20(underlying2).balanceOf(address(asset2)));
        hevm.assume(_proportionBorrowed > 0);

        supplier1.approve(underlying1, _amount1);
        supplier1.supply(asset1, _amount1);
        supplier1.approve(underlying2, _amount2);
        supplier1.supply(asset2, _amount2);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, 10_000_000 * 1e18);

        (, uint256 borrowable1) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset1);
        (, uint256 borrowable2) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset2);

        // Amounts available in the cTokens
        uint256 compBalance1 = asset1 == cEth
            ? asset1.balance
            : ERC20(underlying1).balanceOf(asset1);
        uint256 compBalance2 = asset2 == cEth
            ? asset2.balance
            : ERC20(underlying2).balanceOf(asset2);

        borrowable1 = borrowable1 > compBalance1 ? compBalance1 : borrowable1;
        borrowable2 = borrowable2 > compBalance2 ? compBalance2 : borrowable2;

        uint256 toBorrow1 = (_amount1 * _proportionBorrowed) / type(uint8).max;
        toBorrow1 = toBorrow1 > borrowable1 / 2 ? borrowable1 / 2 : toBorrow1;
        uint256 toBorrow2 = (_amount2 * _proportionBorrowed) / type(uint8).max;
        toBorrow2 = toBorrow2 > borrowable2 / 2 ? borrowable2 / 2 : toBorrow2;

        borrower1.borrow(asset1, toBorrow1);
        borrower1.borrow(asset2, toBorrow2);

        supplier1.withdraw(asset1, _amount1);
        supplier1.withdraw(asset2, _amount2);
    }
}
