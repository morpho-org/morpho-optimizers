// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";
import "./TestSetup.sol";

import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./SimplePriceOracle.sol";
import "./User.sol";
import "./Attacker.sol";

contract GovernanceTest is TestSetup {
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

    // Governance functions
    // Should revert when at least when a market in input is not a real market
    function testFail_revert_on_not_real_market() public {
        marketsManager.createMarket(usdt, WAD, type(uint256).max);
    }

    // Governance functions
    // Only Owner should be able to create markets in peer-to-peer
    function testFail_only_owner_can_create_markets_1() public {
        supplier1.createMarket(usdt, WAD, type(uint256).max);
    }

    function testFail_only_owner_can_create_markets_2() public {
        borrower1.createMarket(usdt, WAD, type(uint256).max);
    }

    function test_only_owner_can_create_markets() public {
        marketsManager.createMarket(aWeth, WAD, type(uint256).max);
    }

    // Governance functions
    // marketsManagerForAave should not be changed after already set by Owner
    function testFail_marketsManager_should_not_be_changed() public {
        marketsManager.setPositionsManager(address(fakePositionsManager));
    }

    // Governance functions
    // Only Owner should be able to update cap value
    function test_only_owner_can_update_cap_value() public {
        uint256 newCapValue = 2 * 1e18;
        marketsManager.updateCapValue(aUsdc, newCapValue);
    }

    function testFail_only_owner_can_update_cap_value_1() public {
        uint256 newCapValue = 2 * 1e18;
        supplier1.updateCapValue(aUsdc, newCapValue);
    }

    function testFail_only_owner_can_update_cap_value_2() public {
        uint256 newCapValue = 2 * 1e18;
        borrower1.updateCapValue(aUsdc, newCapValue);
    }

    // Governance functions
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

    // Governance functions
    // Should update NMAX
    function test_should_update_nmax() public {
        uint16 newNMAX = 3000;

        marketsManager.setMaxNumberOfUsersInTree(newNMAX);
        assertEq(positionsManager.NMAX(), newNMAX);
    }

    function testFail_should_update_nmax_1() public {
        supplier1.setMaxNumberOfUsersInTree(3000);
    }

    function testFail_should_update_nmax_2() public {
        borrower1.setMaxNumberOfUsersInTree(3000);
    }

    function testFail_should_update_nmax_3() public {
        positionsManager.setMaxNumberOfUsersInTree(3000);
    }
}
