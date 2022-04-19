// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestMarketsManager is TestSetup {
    using CompoundMath for uint256;

    function testShoudDeployContractWithTheRightValues() public {
        assertEq(
            marketsManager.supplyP2PExchangeRate(cDai),
            2 * 10**(16 + IERC20Metadata(ICToken(cDai).underlying()).decimals() - 8)
        );
        assertEq(
            marketsManager.borrowP2PExchangeRate(cDai),
            2 * 10**(16 + IERC20Metadata(ICToken(cDai).underlying()).decimals() - 8)
        );
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        hevm.expectRevert(LibMarketsManager.MarketCreationFailedOnCompound.selector);
        marketsManager.createMarket(address(supplier1));
    }

    function testOnlyOwnerCanCreateMarkets() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("LibDiamond: Must be contract owner");
            supplier1.createMarket(pools[i]);

            hevm.expectRevert("LibDiamond: Must be contract owner");
            borrower1.createMarket(pools[i]);
        }

        marketsManager.createMarket(cAave);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("LibDiamond: Must be contract owner");
            supplier1.setReserveFactor(cDai, 1111);

            hevm.expectRevert("LibDiamond: Must be contract owner");
            borrower1.setReserveFactor(cDai, 1111);
        }

        marketsManager.setReserveFactor(cDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        marketsManager.setReserveFactor(cDai, 1111);
        assertEq(marketsManager.reserveFactor(cDai), 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        ICToken cToken = ICToken(cAave);
        marketsManager.createMarket(cAave);

        assertTrue(marketsManager.isCreated(cAave));
        assertEq(
            marketsManager.supplyP2PExchangeRate(cAave),
            2 * 10**(16 + IERC20Metadata(cToken.underlying()).decimals() - 8)
        );
        assertEq(
            marketsManager.borrowP2PExchangeRate(cAave),
            2 * 10**(16 + IERC20Metadata(cToken.underlying()).decimals() - 8)
        );
    }

    function testShouldSetmaxGasWithRightValues() public {
        Types.MaxGas memory newMaxGas = Types.MaxGas({supply: 1, borrow: 1, withdraw: 1, repay: 1});

        positionsManager.setMaxGas(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = positionsManager.maxGas();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier1.setMaxGas(newMaxGas);

        hevm.expectRevert("LibDiamond: Must be contract owner");
        borrower1.setMaxGas(newMaxGas);
    }

    function testOnlyOwnerCanSetNDS() public {
        uint8 newNDS = 30;

        positionsManager.setNDS(newNDS);
        assertEq(positionsManager.NDS(), newNDS);

        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier1.setNDS(newNDS);

        hevm.expectRevert("LibDiamond: Must be contract owner");
        borrower1.setNDS(newNDS);
    }

    function test_only_owner_should_flip_market_strategy() public {
        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier1.setNoP2P(cDai, true);

        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier2.setNoP2P(cDai, true);

        marketsManager.setNoP2P(cDai, true);
        assertTrue(marketsManager.noP2P(cDai));
    }

    function testOnlyOwnerShouldBeAbleToUpdateInterestRates() public {
        IInterestRates interestRatesV2 = new InterestRatesV1();

        hevm.prank(address(0));
        hevm.expectRevert("LibDiamond: Must be contract owner");
        marketsManager.setInterestRates(interestRatesV2);

        marketsManager.setInterestRates(interestRatesV2);
        assertEq(address(marketsManager.interestRates()), address(interestRatesV2));
    }
}
