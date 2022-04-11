// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestMarketsManager is TestSetup {
    using Math for uint256;

    function testShoudDeployContractWithTheRightValues() public {
        assertEq(marketsManager.supplyP2PExchangeRate(aDai), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aDai), RAY);
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        marketsManager.createMarket(address(supplier1));
    }

    function testOnlyOwnerCanCreateMarkets() public {
        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(underlying);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(underlying);
        }

        marketsManager.createMarket(weth);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(aDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(aDai, 1111);
        }

        marketsManager.setReserveFactor(aDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        marketsManager.setReserveFactor(aDai, 1111);
        assertEq(marketsManager.reserveFactor(aDai), 1111);
    }

    function testPositionsManagerShouldBeSetOnlyOnce() public {
        hevm.expectRevert(abi.encodeWithSignature("PositionsManagerAlreadySet()"));
        marketsManager.setPositionsManager(address(fakePositionsManagerImpl));
    }

    function testShouldCreateMarketWithTheRightValues() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        (uint256 expectedSPY, ) = interestRates.computeRates(
            data.currentLiquidityRate,
            data.currentVariableBorrowRate,
            0
        );
        marketsManager.createMarket(aave);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.supplyP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.supplyP2PExchangeRate(aAave), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aAave), RAY);
    }

    function testShouldSetmaxGasWithRightValues() public {
        PositionsManagerForAaveStorage.MaxGas memory newMaxGas = PositionsManagerForAaveStorage
        .MaxGas({supply: 1, borrow: 1, withdraw: 1, repay: 1});

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

    function testOnlyOwnerCanFlipMarketStrategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setNoP2P(aDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setNoP2P(aDai, true);

        marketsManager.setNoP2P(aDai, true);
        assertTrue(marketsManager.noP2P(aDai));
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
