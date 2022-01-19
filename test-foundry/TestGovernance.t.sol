// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestGovernance is TestSetup {
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
        hevm.expectRevert("");
        marketsManager.createMarket(usdt, WAD, type(uint256).max);
    }

    // Only Owner should be able to create markets in peer-to-peer
    function test_only_owner_can_create_markets_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(pools[i], WAD, type(uint256).max);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(pools[i], WAD, type(uint256).max);
        }

        marketsManager.createMarket(aWeth, WAD, type(uint256).max);
    }

    // marketsManagerForAave should not be changed after already set by Owner
    function test_marketsManager_should_not_be_changed() public {
        hevm.expectRevert(abi.encodeWithSignature("PositionsManagerAlreadySet()"));
        marketsManager.setPositionsManager(address(fakePositionsManager));
    }

    // Only Owner should be able to set cap value
    function test_only_owner_can_set_cap_value() public {
        uint256 newCapValue = 2 * 1e18;
        marketsManager.setCapValue(aUsdc, newCapValue);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setCapValue(aUsdc, newCapValue);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setCapValue(aUsdc, newCapValue);
    }

    // Should create a market the with right values
    function test_create_market_with_right_values() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;
        marketsManager.createMarket(aAave, WAD, type(uint256).max);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.supplyP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.borrowP2PSPY(aAave), expectedSPY);
        assertEq(marketsManager.supplyP2PExchangeRate(aAave), RAY);
        assertEq(marketsManager.borrowP2PExchangeRate(aAave), RAY);
    }

    // Should set NMAX
    function test_should_set_nmax() public {
        uint16 newNMAX = 3000;

        positionsManager.setNmaxForMatchingEngine(newNMAX);
        assertEq(positionsManager.NMAX(), newNMAX);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        supplier1.setNmaxForMatchingEngine(newNMAX);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        borrower1.setNmaxForMatchingEngine(newNMAX);
    }
}
