// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestMarketsManager is TestSetup {
    using Math for uint256;

    function testShoudDeployContractWithTheRightValues() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(dai);
        (uint256 expectedSPY, ) = interestRates.computeRates(
            data.currentLiquidityRate,
            data.currentVariableBorrowRate,
            0
        );

        assertEq(marketsManager.supplyP2PSPY(aDai), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aDai), expectedSPY);
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

    function testRatesShouldBeUpdatedWithTheRightValues() public {
        borrower1.updateRates(aDai);
        uint256 firstBlockTimestamp = block.timestamp;

        DataTypes.ReserveData memory data = lendingPool.getReserveData(dai);
        (uint256 expectedSPY, ) = interestRates.computeRates(
            data.currentLiquidityRate,
            data.currentVariableBorrowRate,
            0
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);

        assertEq(marketsManager.supplyP2PSPY(aDai), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aDai), expectedSPY);
        assertEq(supplyP2PExchangeRate, RAY);
        assertEq(borrowP2PExchangeRate, RAY);

        hevm.warp(block.timestamp + 100000);
        borrower1.updateRates(aDai);
        uint256 secondBlockTimestamp = block.timestamp;

        data = lendingPool.getReserveData(dai);
        (uint256 supplySPY, uint256 borrowSPY) = interestRates.computeRates(
            data.currentLiquidityRate,
            data.currentVariableBorrowRate,
            0
        );

        assertEq(marketsManager.supplyP2PSPY(aDai), supplySPY);
        assertEq(marketsManager.borrowP2PSPY(aDai), borrowSPY);

        uint256 newBorrowP2PExchangeRate = borrowP2PExchangeRate.rayMul(
            computeCompoundedInterest(borrowSPY, secondBlockTimestamp - firstBlockTimestamp)
        );
        uint256 newSupplyP2PExchangeRate = supplyP2PExchangeRate.rayMul(
            computeCompoundedInterest(supplySPY, secondBlockTimestamp - firstBlockTimestamp)
        );

        borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        assertEq(supplyP2PExchangeRate, newSupplyP2PExchangeRate);
        assertEq(borrowP2PExchangeRate, newBorrowP2PExchangeRate);
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
