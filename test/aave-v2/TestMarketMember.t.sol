// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestMarketMember is TestSetup {
    function testShouldNotWithdrawWhenNotMarketMember() public {
        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier1.withdraw(aDai, 1 ether);
    }

    function testShouldNotRepayWhenNotMarketMember() public {
        supplier1.approve(dai, 1 ether);
        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier1.repay(aDai, 1 ether);
    }

    function testShouldNotLiquidateUserNotOnMemberOfMarketAsCollateral() public {
        supplier1.approve(aave, 1 ether);
        supplier1.supply(aAave, 1 ether);
        supplier1.borrow(aUsdc, to6Decimals(1 ether));

        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier2.liquidate(aUsdc, aDai, address(supplier1), 1 ether);
    }

    function testShouldNotLiquidateUserNotOnMemberOfMarketAsBorrow() public {
        supplier1.approve(aave, 1 ether);
        supplier1.supply(aAave, 1 ether);
        supplier1.borrow(aUsdc, to6Decimals(1 ether));

        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier2.liquidate(aDai, aAave, address(supplier1), 1 ether);
    }
}
