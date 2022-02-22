// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestMarketsManagerGetters is TestSetup {
    function test_getAllMarkets() public {
        address[] memory allMarkets = marketsManager.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }

    function test_getMarketData() public {
        (
            uint256 supplyP2PSPY,
            uint256 borrowP2PSPY,
            uint256 supplyP2PExchangeRate,
            uint256 borrowP2PExchangeRate,
            uint256 exchangeRatesLastUpdateTimestamp,
            IPositionsManagerForAave.Delta memory delta
        ) = marketsManager.getMarketData(aDai);

        assertEq(supplyP2PSPY, marketsManager.supplyP2PSPY(aDai));
        assertEq(borrowP2PSPY, marketsManager.borrowP2PSPY(aDai));
        assertEq(supplyP2PExchangeRate, marketsManager.supplyP2PExchangeRate(aDai));
        assertEq(borrowP2PExchangeRate, marketsManager.borrowP2PExchangeRate(aDai));
        assertEq(
            exchangeRatesLastUpdateTimestamp,
            marketsManager.exchangeRatesLastUpdateTimestamp(aDai)
        );
        (
            uint256 supplyP2PDelta,
            uint256 borrowP2PDelta,
            uint256 supplyP2PAmount,
            uint256 borrowP2PAmount
        ) = positionsManager.deltas(aDai);

        assertEq(delta.supplyP2PDelta, supplyP2PDelta);
        assertEq(delta.borrowP2PDelta, borrowP2PDelta);
        assertEq(delta.supplyP2PAmount, supplyP2PAmount);
        assertEq(delta.borrowP2PAmount, borrowP2PAmount);
    }

    function test_getMarketConfiguration() public {
        (bool isCreated, bool noP2P, uint256 threshold) = marketsManager.getMarketConfiguration(
            aDai
        );

        assertTrue(isCreated == marketsManager.isCreated(aDai));
        assertTrue(noP2P == marketsManager.noP2P(aDai));
        assertEq(threshold, positionsManager.threshold(aDai));
    }

    function test_getUpdatedBorrowP2PExchangeRate() public {
        hevm.warp(block.timestamp + (365 days));

        uint256 newBorrowP2PExchangeRate = marketsManager.getUpdatedBorrowP2PExchangeRate(aDai);
        marketsManager.updateRates(aDai);
        assertEq(newBorrowP2PExchangeRate, marketsManager.borrowP2PExchangeRate(aDai));
    }

    function test_getUpdatedSupplyP2PExchangeRate() public {
        hevm.warp(block.timestamp + (365 days));

        uint256 newSupplyP2PExchangeRate = marketsManager.getUpdatedSupplyP2PExchangeRate(aDai);
        marketsManager.updateRates(aDai);
        assertEq(newSupplyP2PExchangeRate, marketsManager.supplyP2PExchangeRate(aDai));
    }
}
