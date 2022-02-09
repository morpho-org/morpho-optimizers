// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

import "@contracts/aave/libraries/aave/WadRayMath.sol";

contract TestGovernance is TestSetup {
    using WadRayMath for uint256;

    // ==============
    // = Deployment =
    // ==============

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
        assertEq(positionsManager.threshold(aDai), WAD);
    }

    // ========================
    // = Governance functions =
    // ========================

    // Should revert when the function is called with an improper market
    function test_revert_on_not_real_market() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        marketsManager.createMarket(address(supplier1), WAD);
    }

    // Only Owner should be able to create markets in peer-to-peer
    function test_only_owner_can_create_markets_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(underlyings[i], WAD);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(underlyings[i], WAD);
        }

        marketsManager.createMarket(weth, WAD);
    }

    // Only Owner should be able to set threshold
    function test_only_owner_can_set_threshold() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setThreshold(pools[i], WAD);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setThreshold(pools[i], WAD);
        }

        marketsManager.setThreshold(aDai, WAD);
    }

    // Threshold should be updated
    function test_threshold_should_be_updated() public {
        marketsManager.setThreshold(aDai, 5 * WAD);
        assertEq(positionsManager.threshold(aDai), 5 * WAD);
    }

    // Only Owner should be able to set reserve factor
    function test_only_owner_can_set_reserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(1111);
        }

        marketsManager.setReserveFactor(1111);
    }

    // Reserve factor should be updated
    function test_reserveFactor_should_be_updated() public {
        marketsManager.setReserveFactor(1111);
        assertEq(marketsManager.reserveFactor(), 1111);
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

        uint256 supplySPY = (expectedSPY * (MAX_BASIS_POINTS - marketsManager.reserveFactor())) /
            MAX_BASIS_POINTS;
        uint256 borrowSPY = (expectedSPY * (MAX_BASIS_POINTS + marketsManager.reserveFactor())) /
            MAX_BASIS_POINTS;
        assertEq(marketsManager.supplyP2PSPY(aDai), supplySPY);
        assertEq(marketsManager.borrowP2PSPY(aDai), borrowSPY);

        uint256 newBorrowP2PExchangeRate = borrowP2PExchangeRate.rayMul(
            (WadRayMath.ray() + borrowSPY).rayPow(secondBlockTimestamp - firstBlockTimestamp)
        );
        uint256 newSupplyP2PExchangeRate = supplyP2PExchangeRate.rayMul(
            (WadRayMath.ray() + supplySPY).rayPow(secondBlockTimestamp - firstBlockTimestamp)
        );

        borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        assertEq(supplyP2PExchangeRate, newSupplyP2PExchangeRate);
        assertEq(borrowP2PExchangeRate, newBorrowP2PExchangeRate);
    }

    // marketsManagerForAave should not be changed after already set by Owner
    function test_positionsManager_should_not_be_changed() public {
        hevm.expectRevert(abi.encodeWithSignature("PositionsManagerAlreadySet()"));
        marketsManager.setPositionsManager(address(fakePositionsManager));
    }

    // Should create a market the with right values
    function test_create_market_with_right_values() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;
        marketsManager.createMarket(aave, WAD);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.supplyP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.supplyP2PExchangeRate(aAave), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aAave), RAY);
    }

    // Should set NMAX
    function test_should_set_nmax() public {
        uint8 newNMAX = 30;

        positionsManager.setNmaxForMatchingEngine(newNMAX);
        assertEq(positionsManager.NMAX(), newNMAX);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        supplier1.setNmaxForMatchingEngine(newNMAX);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        borrower1.setNmaxForMatchingEngine(newNMAX);
    }

    function test_only_owner_should_flip_market_strategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setNoP2P(aDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setNoP2P(aDai, true);

        marketsManager.setNoP2P(aDai, true);
        assertTrue(marketsManager.noP2P(aDai));
    }

    function test_only_owner_can_set_aave_incentives_controller_on_rewards_manager() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setAaveIncentivesControllerOnRewardsManager(address(0));

        rewardsManager.setAaveIncentivesController(address(1));
        assertEq(address(rewardsManager.aaveIncentivesController()), address(1));
    }
}
