// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using Math for uint256;

    // Deployment
    // Should deploy the contract with the right values
    function test_deploy_contract() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(dai);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;

        assertEq(marketsManager.supplyP2PSPY(aDai), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aDai), expectedSPY);
        assertEq(marketsManager.supplyP2PExchangeRate(aDai), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aDai), RAY);
    }

    // ========================
    // = Governance functions =
    // ========================

    // Should revert when the function is called with an improper market
    function test_revert_on_not_real_market() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        marketsManager.createMarket(address(supplier1));
    }

    // Only Owner should be able to create markets in peer-to-peer
    function test_only_owner_can_create_markets_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(underlying);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(underlying);
        }

        marketsManager.createMarket(weth);
    }

    // Only Owner should be able to set reserve factor
    function test_only_owner_can_set_reserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(aDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(aDai, 1111);
        }

        marketsManager.setReserveFactor(aDai, 1111);
    }

    // Reserve factor should be updated
    function test_reserveFactor_should_be_updated() public {
        marketsManager.setReserveFactor(aDai, 1111);
        assertEq(marketsManager.reserveFactor(aDai), 1111);
    }

    // Anyone can update the rates
    function test_rates_should_be_updated() public {
        borrower1.updateRates(aDai);
        uint256 firstBlockTimestamp = block.timestamp;

        DataTypes.ReserveData memory data = lendingPool.getReserveData(dai);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;

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
        expectedSPY =
            (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;

        uint256 supplySPY = (expectedSPY *
            (MAX_BASIS_POINTS - marketsManager.reserveFactor(aDai))) / MAX_BASIS_POINTS;
        uint256 borrowSPY = (expectedSPY *
            (MAX_BASIS_POINTS + marketsManager.reserveFactor(aDai))) / MAX_BASIS_POINTS;
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

    // marketsManagerForAave should not be changed after already set by Owner
    function test_positionsManager_should_not_be_changed() public {
        hevm.expectRevert(abi.encodeWithSignature("PositionsManagerAlreadySet()"));
        marketsManager.setPositionsManager(address(fakePositionsManagerImpl));
    }

    // Should create a market the with right values
    function test_create_market_with_right_values() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;
        marketsManager.createMarket(aave);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.supplyP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.supplyP2PExchangeRate(aAave), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aAave), RAY);
    }

    // Only MarketsaManager's Owner should set NMAX
    function test_should_set_maxGas() public {
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

    // Only MarketsaManager's Owner should set NDS
    function test_should_set_nds() public {
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
        supplier1.setNoP2P(aDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setNoP2P(aDai, true);

        marketsManager.setNoP2P(aDai, true);
        assertTrue(marketsManager.noP2P(aDai));
    }
}
