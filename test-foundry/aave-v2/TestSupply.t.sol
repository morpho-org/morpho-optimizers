// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";
import "./helpers/FlashLoan.sol";
import "../../contracts/aave-v2/libraries/Types.sol";
import "@forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TestSupply is TestSetup {
    using stdStorage for StdStorage;
    using WadRayMath for uint256;

    mapping(address => User) users;

    function logFirsts() public view {
        address current = morpho.getHead(aDai, Types.PositionType.SUPPLIERS_ON_POOL);
        string memory a;
        for (uint256 i; i < 8; i++) {
            (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, current);
            string memory added = string.concat(Strings.toString(onPool), ", ");
            a = string.concat(a, added);
            if (current != address(0))
                current = morpho.getNext(aDai, Types.PositionType.SUPPLIERS_ON_POOL, current);
        }

        console.log(a);
    }

    function getNewUser(address addr) public returns (User usr) {
        uint256 bigAmount = 1_000_000 ether;
        usr = users[addr];
        if (address(usr) == address(0)) {
            usr = new User(morpho);
            users[addr] = usr;
            fillUserBalances(usr);
            usr.approve(dai, type(uint256).max);
            usr.approve(wEth, type(uint256).max);
            usr.supply(aWeth, bigAmount); // so that users are always collateralized
        }
    }

    function testFirstMonthDAI() public {
        User currentUser;
        createMarket(aWeth);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.borrow(
        //     aDai,
        //     0x00000000000000000000000000000000000000000000054b40b1f852bd800000
        // );
        // console.log("borrow", 0x00000000000000000000000000000000000000000000054b40b1f852bd800000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.supply(
        //     aDai,
        //     0x00000000000000000000000000000000000000000000054b40b1f852bd800000
        // );
        // console.log("supply", 0x00000000000000000000000000000000000000000000054b40b1f852bd800000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.withdraw(
        //     aDai,
        //     0x00000000000000000000000000000000000000000000043c33c1937564800000
        // );
        // console.log("withdraw", 0x00000000000000000000000000000000000000000000043c33c1937564800000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.repay(aDai, 0x00000000000000000000000000000000000000000000043c33c1937564800000);
        // console.log("repay", 0x00000000000000000000000000000000000000000000043c33c1937564800000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.withdraw(
        //     aDai,
        //     0x00000000000000000000000000000000000000000000010f263bd8e952200000
        // );
        // console.log("withdraw", 0x00000000000000000000000000000000000000000000010f263bd8e952200000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.repay(aDai, 0x00000000000000000000000000000000000000000000010f263bd8e952200000);
        // console.log("repay", 0x00000000000000000000000000000000000000000000010f263bd8e952200000);
        // currentUser = getNewUser(
        //     address(
        //         uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
        //     )
        // );
        // currentUser.repay(aDai, 0x0000000000000000000000000000000000000000000000000f04892dff9c61b0);
        // console.log("repay", 0x0000000000000000000000000000000000000000000000000f04892dff9c61b0);

        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000006e632701fd42a9b856294a2172dd63f03eb957c5))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000000015af1d78b58c40000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000006e632701fd42a9b856294a2172dd63f03eb957c5))
            )
        );
        currentUser.borrow(
            aDai,
            0x0000000000000000000000000000000000000000000000004f89dc938286aff8
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000264c86dbbd2e4165fbbf0c35b0ddf0e00aec6b31))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000000056bc75e2d63100000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000006abfd6139c7c3cc270ee2ce132e309f59caaf6a2))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000001b1ae4d6e2ef500000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000006abfd6139c7c3cc270ee2ce132e309f59caaf6a2))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000069c5f3028f93e0000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000f7253a0e87e39d2cd6365919d4a3d56d431d0041))
            )
        );
        currentUser.supply(
            aDai,
            0x000000000000000000000000000000000000000000000015b81d1d5ac8f69ac0
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000005853ed4f26a3fcea565b3fbc698bb19cdf6deb85))
            )
        );
        currentUser.supply(
            aDai,
            0x000000000000000000000000000000000000000000000000016345785d8a0000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000005853ed4f26a3fcea565b3fbc698bb19cdf6deb85))
            )
        );
        currentUser.borrow(
            aDai,
            0x000000000000000000000000000000000000000000000000001b5b22505311f4
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x00000000000000000000000032c52c9e56c7382e9a9e52d53862ff3e6cbcaeee))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000000273f902caf9f57e50
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x00000000000000000000000050e4eb3a74d2be7fd7c0be081754cee2dbeae918))
            )
        );
        currentUser.supply(
            aDai,
            0x000000000000000000000000000000000000000000000002b5e3af16b1880000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000003a91d37bac30c913369e1abc8cad1c13d1ff2e98))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000000000000000005f5e100
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000a1958a37c21372482deff4618baebbec23c9a449))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000002231e1587e466400000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000a1958a37c21372482deff4618baebbec23c9a449))
            )
        );
        currentUser.borrow(
            aDai,
            0x00000000000000000000000000000000000000000000001b1ae4d6e2ef500000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000a1958a37c21372482deff4618baebbec23c9a449))
            )
        );
        currentUser.repay(aDai, 0x00000000000000000000000000000000000000000000001b1ae4d6e2ef500000);
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000005f9d7cef3e9298de2e91ff0cb486ce2c7ffc5144))
            )
        );
        currentUser.supply(
            aDai,
            0x000000000000000000000000000000000000000000000001158e460913d00000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000a1958a37c21372482deff4618baebbec23c9a449))
            )
        );
        currentUser.withdraw(
            aDai,
            0x000000000000000000000000000000000000000000000222fac9693cdc800000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.borrow(
            aDai,
            0x00000000000000000000000000000000000000000000054b40b1f852bd800000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000054b40b1f852bd800000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000f53feaeb035361c046e5669745695e450ebb4028))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000d3c21bcecceda0000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000f53feaeb035361c046e5669745695e450ebb4028))
            )
        );
        currentUser.withdraw(
            aDai,
            0x0000000000000000000000000000000000000000000089a49213386740000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000f53feaeb035361c046e5669745695e450ebb4028))
            )
        );
        currentUser.borrow(
            aDai,
            0x000000000000000000000000000000000000000000000a968163f0a57b000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x00000000000000000000000016c2312b7168f0e268751a4d5d73953176d87768))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000006194049f30f7200000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x000000000000000000000000046f601cbcbfa162228897ac75c9b61daf5cee5f))
            )
        );
        currentUser.borrow(
            aDai,
            0x0000000000000000000000000000000000000000000000a2a15d09519be00000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000007bfee91193d9df2ac0bfe90191d40f23c773c060))
            )
        );
        currentUser.supply(
            aDai,
            0x0000000000000000000000000000000000000000000069e4a419b0df64000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x00000000000000000000000047b023db19b34519aa34c39134b508cac2c1efcb))
            )
        );
        currentUser.borrow(
            aDai,
            0x000000000000000000000000000000000000000000007ad1dcedb44c60000000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.withdraw(
            aDai,
            0x00000000000000000000000000000000000000000000043c33c1937564800000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.repay(aDai, 0x00000000000000000000000000000000000000000000043c33c1937564800000);
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.withdraw(
            aDai,
            0x00000000000000000000000000000000000000000000010f263bd8e952200000
        );
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000009ed5194f7506d71eed9facb203b80ad03ae8f2ed))
            )
        );
        currentUser.repay(aDai, 0x00000000000000000000000000000000000000000000010f263bd8e952200000);
        logFirsts();
        currentUser = getNewUser(
            address(
                uint160(uint256(0x0000000000000000000000007bfee91193d9df2ac0bfe90191d40f23c773c060))
            )
        );
        currentUser.supply(
            aDai,
            0x00000000000000000000000000000000000000000000ddc21a99e84720000000
        );
        logFirsts();
    }

    // There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function testSupply1() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = amount.rayDiv(normalizedIncome);

        testEquality(IERC20(aDai).balanceOf(address(morpho)), amount);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        testEquality(onPool, expectedOnPool);
        testEquality(inP2P, 0);
    }

    // There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function testSupply2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;

        supplier1.approve(dai, address(morpho), amount);
        supplier1.supply(aDai, amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        testEquality(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedSupplyBalanceInP2P = amount.rayDiv(p2pSupplyIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, inP2PSupplier);
    }

    // There is 1 available borrower, he doesn't match 100% of the supplier liquidity. Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function testSupply3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, 2 * amount);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedSupplyBalanceInP2P = amount.rayDiv(p2pSupplyIndex);

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);
        uint256 expectedSupplyBalanceOnPool = amount.rayDiv(normalizedIncome);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, inP2PSupplier);
    }

    // There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function testSupply4() public {
        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2PInUnderlying;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));

            expectedInP2PInUnderlying = inP2P.rayMul(p2pSupplyIndex);

            testEquality(expectedInP2PInUnderlying, amountPerBorrower, "amount per borrower");
            testEquality(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 expectedInP2P = amount.rayDiv(morpho.p2pBorrowIndex(aDai));

        testEquality(inP2P, expectedInP2P);
        testEquality(onPool, 0);
    }

    // The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`. ⚠️ most gas expensive supply scenario.
    function testSupply5() public {
        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2PInUnderlying;
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));

            expectedInP2PInUnderlying = inP2P.rayMul(p2pBorrowIndex);

            testEquality(expectedInP2PInUnderlying, amountPerBorrower, "borrower in peer-to-peer");
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 expectedInP2P = (amount / 2).rayDiv(morpho.p2pSupplyIndex(aDai));
        uint256 expectedOnPool = (amount / 2).rayDiv(normalizedIncome);

        testEquality(inP2P, expectedInP2P, "in peer-to-peer");
        testEquality(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(aDai, amount);
        supplier1.supply(aDai, amount);

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = (2 * amount).rayDiv(normalizedIncome);

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testFailSupplyZero() public {
        morpho.supply(aDai, msg.sender, 0, type(uint256).max);
    }

    function testSupplyRepayOnBehalf() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        // Someone repays on behalf of Morpho.
        supplier2.approve(dai, address(pool), amount);
        hevm.prank(address(supplier2));
        pool.repay(dai, amount, 2, address(morpho));
        hevm.stopPrank();

        // Supplier 1 supply in peer-to-peer. Not supposed to revert.
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
    }

    function testSupplyOnBehalf() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        hevm.prank(address(supplier1));
        morpho.supply(aDai, address(supplier2), amount);

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = amount.rayDiv(poolSupplyIndex);

        assertEq(ERC20(aDai).balanceOf(address(morpho)), amount, "balance of aToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier2));

        assertApproxEqAbs(onPool, expectedOnPool, 1, "on pool");
        assertEq(inP2P, 0, "in peer-to-peer");
    }

    function testSupplyAfterFlashloan() public {
        uint256 amount = 1_000 ether;
        uint256 flashLoanAmount = 10_000 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        FlashLoan flashLoan = new FlashLoan(pool);
        vm.prank(address(supplier2));
        ERC20(dai).transfer(address(flashLoan), 10_000 ether); // to pay the premium.
        flashLoan.callFlashLoan(dai, flashLoanAmount);

        vm.warp(block.timestamp + 1);
        supplier1.supply(aDai, amount);
    }
}
