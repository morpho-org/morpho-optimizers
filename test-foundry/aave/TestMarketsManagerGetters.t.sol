// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestMarketsManagerGetters is TestSetup {
    function testGetAllMarkets() public {
        address[] memory allMarkets = marketsManager.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }

    function testGetMarketData() public {
        (
            uint256 supplyP2PSPY,
            uint256 borrowP2PSPY,
            uint256 supplyP2PExchangeRate,
            uint256 borrowP2PExchangeRate,
            uint256 exchangeRatesLastUpdateTimestamp,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
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

        assertEq(supplyP2PDelta_, supplyP2PDelta);
        assertEq(borrowP2PDelta_, borrowP2PDelta);
        assertEq(supplyP2PAmount_, supplyP2PAmount);
        assertEq(borrowP2PAmount_, borrowP2PAmount);
    }

    function testGetMarketConfiguration() public {
        (bool isCreated, bool noP2P) = marketsManager.getMarketConfiguration(aDai);

        assertTrue(isCreated == marketsManager.isCreated(aDai));
        assertTrue(noP2P == marketsManager.noP2P(aDai));
    }

    function testGetUpdatedBorrowP2PExchangeRate() public {
        hevm.warp(block.timestamp + (365 days));

        uint256 newBorrowP2PExchangeRate = marketsManager.getUpdatedBorrowP2PExchangeRate(aDai);
        marketsManager.updateRates(aDai);
        assertEq(newBorrowP2PExchangeRate, marketsManager.borrowP2PExchangeRate(aDai));
    }

    function testGetUpdatedSupplyP2PExchangeRate() public {
        hevm.warp(block.timestamp + (365 days));

        uint256 newSupplyP2PExchangeRate = marketsManager.getUpdatedSupplyP2PExchangeRate(aDai);
        marketsManager.updateRates(aDai);
        assertEq(newSupplyP2PExchangeRate, marketsManager.supplyP2PExchangeRate(aDai));
    }
}
