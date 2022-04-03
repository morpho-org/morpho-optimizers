// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestMarketsManager is TestSetup {
    using CompoundMath for uint256;

    function testShoudDeployContractWithTheRightValues() public {
        ICToken cToken = ICToken(cDai);
        uint256 expectedBPY = (cToken.supplyRatePerBlock() + cToken.borrowRatePerBlock()) / 2;

        assertEq(marketsManager.supplyP2PBPY(cDai), expectedBPY);
        assertEq(marketsManager.borrowP2PBPY(cDai), expectedBPY);
        assertEq(marketsManager.supplyP2PExchangeRate(cDai), WAD);
        assertEq(marketsManager.borrowP2PExchangeRate(cDai), WAD);
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        hevm.expectRevert(MarketsManagerForCompound.MarketCreationFailedOnCompound.selector);
        marketsManager.createMarket(address(supplier1));
    }

    function testOnlyOwnerCanCreateMarkets() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(pools[i]);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(pools[i]);
        }

        marketsManager.createMarket(cEth);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(cDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(cDai, 1111);
        }

        marketsManager.setReserveFactor(cDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        marketsManager.setReserveFactor(cDai, 1111);
        assertEq(marketsManager.reserveFactor(cDai), 1111);
    }

    function testRatesShouldBeUpdatedWithTheRightValues() public {
        borrower1.updateRates(cDai);

        ICToken cToken = ICToken(cDai);
        uint256 expectedBPY = (cToken.supplyRatePerBlock() + cToken.borrowRatePerBlock()) / 2;

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);

        assertEq(marketsManager.supplyP2PBPY(cDai), expectedBPY);
        assertEq(marketsManager.borrowP2PBPY(cDai), expectedBPY);
        assertEq(supplyP2PExchangeRate, WAD);
        assertEq(borrowP2PExchangeRate, WAD);

        hevm.roll(block.number + 100);
        borrower1.updateRates(cDai);

        uint256 newBorrowP2PExchangeRate = borrowP2PExchangeRate.mul(
            _computeCompoundedInterest(expectedBPY, 100)
        );
        uint256 newSupplyP2PExchangeRate = supplyP2PExchangeRate.mul(
            _computeCompoundedInterest(expectedBPY, 100)
        );

        borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        assertEq(supplyP2PExchangeRate, newSupplyP2PExchangeRate);
        assertEq(borrowP2PExchangeRate, newBorrowP2PExchangeRate);

        expectedBPY = (cToken.supplyRatePerBlock() + cToken.borrowRatePerBlock()) / 2;

        uint256 supplyBPY = (expectedBPY *
            (MAX_BASIS_POINTS - marketsManager.reserveFactor(cDai))) / MAX_BASIS_POINTS;
        uint256 borrowBPY = (expectedBPY *
            (MAX_BASIS_POINTS + marketsManager.reserveFactor(cDai))) / MAX_BASIS_POINTS;
        assertEq(marketsManager.supplyP2PBPY(cDai), supplyBPY);
        assertEq(marketsManager.borrowP2PBPY(cDai), borrowBPY);
    }

    function testPositionsManagerShouldBeSetOnlyOnce() public {
        hevm.expectRevert(MarketsManagerForCompound.PositionsManagerAlreadySet.selector);
        marketsManager.setPositionsManager(address(fakePositionsManagerImpl));
    }

    function testShouldCreateMarketWithTheRightValues() public {
        ICToken cToken = ICToken(cAave);
        marketsManager.createMarket(cAave);
        uint256 expectedBPY = (cToken.supplyRatePerBlock() + cToken.borrowRatePerBlock()) / 2;

        assertTrue(marketsManager.isCreated(cAave));
        assertEq(marketsManager.supplyP2PBPY(cAave), expectedBPY);
        assertEq(marketsManager.borrowP2PBPY(cAave), expectedBPY);
        assertEq(marketsManager.supplyP2PExchangeRate(cAave), WAD);
        assertEq(marketsManager.borrowP2PExchangeRate(cAave), WAD);
    }

    function testShouldSetmaxGasWithRightValues() public {

            PositionsManagerForCompoundStorage.MaxGas memory newMaxGas
         = PositionsManagerForCompoundStorage.MaxGas({supply: 1, borrow: 1, withdraw: 1, repay: 1});

        positionsManager.setMaxGas(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = positionsManager.maxGas();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setMaxGas(newMaxGas);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setMaxGas(newMaxGas);
    }

    function testOnlyOwnerCanSetNDS() public {
        uint8 newNDS = 30;

        positionsManager.setNDS(newNDS);
        assertEq(positionsManager.NDS(), newNDS);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setNDS(newNDS);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setNDS(newNDS);
    }

    function test_only_owner_should_flip_market_strategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setNoP2P(cDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setNoP2P(cDai, true);

        marketsManager.setNoP2P(cDai, true);
        assertTrue(marketsManager.noP2P(cDai));
    }

    function testOnlyOwnerShouldBeAbleToUpdateInterestRates() public {
        IInterestRates interestRatesV2 = new InterestRatesV1();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        marketsManager.setInterestRates(interestRatesV2);

        marketsManager.setInterestRates(interestRatesV2);
        assertEq(address(marketsManager.interestRates()), address(interestRatesV2));
    }
}
