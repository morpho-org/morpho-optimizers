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

        assertEq(marketsManager.p2pSPY(aDai), expectedSPY);
        assertEq(marketsManager.p2pExchangeRate(aDai), RAY);
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

    // Only Owner should be able to update cap value
    function test_only_owner_can_update_cap_value() public {
        uint256 newCapValue = 2 * 1e18;
        marketsManager.updateCapValue(aUsdc, newCapValue);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.updateCapValue(aUsdc, newCapValue);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.updateCapValue(aUsdc, newCapValue);
    }

    // Should create a market the with right values
    function test_create_market_with_right_values() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;
        marketsManager.createMarket(aAave, WAD, type(uint256).max);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.p2pSPY(aAave), expectedSPY);
        assertEq(marketsManager.p2pExchangeRate(aAave), RAY);
    }

    // Should update NMAX
    function test_should_update_nmax() public {
        uint16 newNMAX = 3000;

        marketsManager.setNmaxForMatchingEngine(newNMAX);
        assertEq(positionsManager.NMAX(), newNMAX);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setNmaxForMatchingEngine(3000);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setNmaxForMatchingEngine(3000);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManager()"));
        positionsManager.setNmaxForMatchingEngine(3000);
    }
}
