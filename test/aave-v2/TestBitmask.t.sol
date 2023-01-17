// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestBitmask is TestSetup {
    function testOneUserSupplyMany() public {
        supplier1.approve(dai, 42 ether);
        supplier1.supply(aDai, 42 ether);

        supplier1.approve(usdc, to6Decimals(23 ether));
        supplier1.supply(aUsdc, to6Decimals(23 ether));

        supplier1.approve(aave, 1 ether);
        supplier1.supply(aAave, 1 ether);

        assertTrue(isSupplying(address(supplier1), aDai));
        assertFalse(isBorrowing(address(supplier1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aDai));

        assertTrue(isSupplying(address(supplier1), aUsdc));
        assertFalse(isBorrowing(address(supplier1), aUsdc));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aUsdc));

        assertTrue(isSupplying(address(supplier1), aAave));
        assertFalse(isBorrowing(address(supplier1), aAave));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aAave));

        assertFalse(isBorrowingAny(address(supplier1)));

        assertFalse(isSupplying(address(supplier1), aWbtc));
        assertFalse(isBorrowing(address(supplier1), aWbtc));
        assertFalse(isSupplyingOrBorrowing(address(supplier1), aWbtc));
    }

    function testOneUserBorrowMany() public {
        borrower1.approve(dai, 42 ether);
        borrower1.supply(aDai, 42 ether);

        borrower1.borrow(aDai, 1 ether);
        borrower1.borrow(aUsdc, to6Decimals(23 ether));
        borrower1.borrow(aUsdt, to6Decimals(2 ether));

        assertTrue(isSupplying(address(borrower1), aDai));
        assertTrue(isBorrowing(address(borrower1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aDai));

        assertFalse(isSupplying(address(borrower1), aUsdc));
        assertTrue(isBorrowing(address(borrower1), aUsdc));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aUsdc));

        assertFalse(isSupplying(address(borrower1), aUsdt));
        assertTrue(isBorrowing(address(borrower1), aUsdt));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aUsdt));

        assertTrue(isBorrowingAny(address(borrower1)));

        assertFalse(isSupplying(address(borrower1), aWbtc));
        assertFalse(isBorrowing(address(borrower1), aWbtc));
        assertFalse(isSupplyingOrBorrowing(address(borrower1), aWbtc));
    }

    function testSupplierLeftMarket() public {
        supplier1.approve(dai, 10 ether);
        supplier1.supply(aDai, 10 ether);

        assertTrue(isSupplying(address(supplier1), aDai));
        assertFalse(isBorrowing(address(supplier1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aDai));

        assertFalse(isBorrowingAny(address(borrower1)));

        supplier1.withdraw(aDai, type(uint256).max);

        assertFalse(isSupplying(address(supplier1), aDai));
        assertFalse(isBorrowing(address(supplier1), aDai));
        assertFalse(isSupplyingOrBorrowing(address(supplier1), aDai));

        assertFalse(isBorrowingAny(address(supplier1)));

        assertFalse(isSupplying(address(supplier1), aWbtc));
        assertFalse(isBorrowing(address(supplier1), aWbtc));
        assertFalse(isSupplyingOrBorrowing(address(supplier1), aWbtc));
    }

    function testBorrowerLeftMarket() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(aDai, 10 ether);

        borrower1.borrow(aUsdc, to6Decimals(5 ether));

        assertTrue(isSupplying(address(borrower1), aDai));
        assertFalse(isBorrowing(address(borrower1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aDai));

        assertFalse(isSupplying(address(borrower1), aUsdc));
        assertTrue(isBorrowing(address(borrower1), aUsdc));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aUsdc));

        assertTrue(isBorrowingAny(address(borrower1)));

        borrower1.approve(usdc, type(uint256).max);
        borrower1.repay(aUsdc, type(uint256).max);

        assertTrue(isSupplying(address(borrower1), aDai));
        assertFalse(isBorrowing(address(borrower1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aDai));

        assertFalse(isSupplying(address(borrower1), aUsdc));
        assertFalse(isBorrowing(address(borrower1), aUsdc));
        assertFalse(isSupplyingOrBorrowing(address(borrower1), aUsdc));

        assertFalse(isBorrowingAny(address(borrower1)));

        borrower1.withdraw(aDai, type(uint256).max);

        assertFalse(isSupplying(address(borrower1), aDai));
        assertFalse(isBorrowing(address(borrower1), aDai));
        assertFalse(isSupplyingOrBorrowing(address(borrower1), aDai));

        assertFalse(isSupplying(address(borrower1), aUsdc));
        assertFalse(isBorrowing(address(borrower1), aUsdc));
        assertFalse(isSupplyingOrBorrowing(address(borrower1), aUsdc));

        assertFalse(isBorrowingAny(address(borrower1)));

        assertFalse(isSupplying(address(borrower1), aWbtc));
        assertFalse(isBorrowing(address(borrower1), aWbtc));
        assertFalse(isSupplyingOrBorrowing(address(borrower1), aWbtc));
    }

    function testBitmaskSupplyOnBehalf() public {
        supplier1.approve(dai, 10 ether);
        hevm.prank(address(supplier1));
        morpho.supply(aDai, address(supplier2), 10 ether);

        assertFalse(isSupplying(address(supplier1), aDai));
        assertTrue(isSupplying(address(supplier2), aDai));
    }

    function testBitmaskRepayOnBehalf() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(aDai, 10 ether);
        borrower1.borrow(aDai, 10 ether / 2);

        supplier1.approve(dai, type(uint256).max);
        hevm.prank(address(supplier1));
        morpho.repay(aDai, address(borrower1), 10 ether / 4);

        assertTrue(isBorrowing(address(borrower1), aDai));
        assertFalse(isSupplying(address(supplier1), aDai));
        assertFalse(isBorrowing(address(supplier1), aDai));
    }

    function isSupplyingOrBorrowing(address _user, address _market) internal view returns (bool) {
        bytes32 bmask = morpho.borrowMask(_market);
        return morpho.userMarkets(_user) & (bmask | (bmask << 1)) != 0;
    }

    function isBorrowing(address _user, address _market) internal view returns (bool) {
        return morpho.userMarkets(_user) & morpho.borrowMask(_market) != 0;
    }

    function isSupplying(address _user, address _market) internal view returns (bool) {
        return morpho.userMarkets(_user) & (morpho.borrowMask(_market) << 1) != 0;
    }

    function isBorrowingAny(address _user) internal view returns (bool) {
        return morpho.userMarkets(_user) & morpho.BORROWING_MASK() != 0;
    }
}
