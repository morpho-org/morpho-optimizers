// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";
import {MorphoStorage} from "@contracts/aave-v2/MorphoStorage.sol";

contract TestBitmask is TestSetup {
    function testOneUserSupplyMany() public {
        createMarket(aWeth);

        supplier1.approve(dai, 42 ether);
        supplier1.supply(aDai, 42 ether);

        supplier1.approve(usdc, to6Decimals(23 ether));
        supplier1.supply(aUsdc, to6Decimals(23 ether));

        supplier1.approve(wEth, 1 ether);
        supplier1.supply(aWeth, 1 ether);

        assertTrue(isSupplying(address(supplier1), aDai));
        assertFalse(isBorrowing(address(supplier1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aDai));

        assertTrue(isSupplying(address(supplier1), aUsdc));
        assertFalse(isBorrowing(address(supplier1), aUsdc));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aUsdc));

        assertTrue(isSupplying(address(supplier1), aWeth));
        assertFalse(isBorrowing(address(supplier1), aWeth));
        assertTrue(isSupplyingOrBorrowing(address(supplier1), aWeth));

        assertFalse(isBorrowingAny(address(supplier1)));

        assertFalse(isSupplying(address(supplier1), aWbtc));
        assertFalse(isBorrowing(address(supplier1), aWbtc));
        assertFalse(isSupplyingOrBorrowing(address(supplier1), aWbtc));
    }

    function testOneUserBorrowMany() public {
        createMarket(aWeth);

        borrower1.approve(dai, 42 ether);
        borrower1.supply(aDai, 42 ether);

        borrower1.borrow(aDai, 1 ether);
        borrower1.borrow(aUsdc, to6Decimals(23 ether));
        borrower1.borrow(aWeth, 1e12 wei);

        assertTrue(isSupplying(address(borrower1), aDai));
        assertTrue(isBorrowing(address(borrower1), aDai));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aDai));

        assertFalse(isSupplying(address(borrower1), aUsdc));
        assertTrue(isBorrowing(address(borrower1), aUsdc));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aUsdc));

        assertFalse(isSupplying(address(borrower1), aWeth));
        assertTrue(isBorrowing(address(borrower1), aWeth));
        assertTrue(isSupplyingOrBorrowing(address(borrower1), aWeth));

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
        return morpho.supplyMarket(_user, _market) || morpho.borrowMarket(_user, _market);
    }

    function isBorrowing(address _user, address _market) internal view returns (bool) {
        return morpho.borrowMarket(_user, _market);
    }

    function isSupplying(address _user, address _market) internal view returns (bool) {
        return morpho.supplyMarket(_user, _market);
    }

    function isBorrowingAny(address _user) internal view returns (bool) {
        return morpho.isBorrower(_user);
    }
}
