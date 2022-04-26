// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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
            uint256 supplyP2PExchangeRate,
            uint256 borrowP2PExchangeRate,
            uint256 lastUpdateBlockNumber,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        ) = marketsManager.getMarketData(cDai);

        assertEq(supplyP2PExchangeRate, marketsManager.supplyP2PExchangeRate(cDai));
        assertEq(borrowP2PExchangeRate, marketsManager.borrowP2PExchangeRate(cDai));
        assertEq(lastUpdateBlockNumber, marketsManager.lastUpdateBlockNumber(cDai));
        (
            uint256 supplyP2PDelta,
            uint256 borrowP2PDelta,
            uint256 supplyP2PAmount,
            uint256 borrowP2PAmount
        ) = positionsManager.deltas(cDai);

        assertEq(supplyP2PDelta_, supplyP2PDelta);
        assertEq(borrowP2PDelta_, borrowP2PDelta);
        assertEq(supplyP2PAmount_, supplyP2PAmount);
        assertEq(borrowP2PAmount_, borrowP2PAmount);
    }

    function testGetMarketConfiguration() public {
        (
            bool isCreated,
            bool noP2P,
            bool isPaused,
            bool isPartialPaused,
            uint256 reserveFactor
        ) = marketsManager.getMarketConfiguration(cDai);

        assertTrue(isCreated == marketsManager.isCreated(cDai));
        assertTrue(noP2P == marketsManager.noP2P(cDai));

        (bool isPaused_, bool isPartialPaused_) = positionsManager.pauseStatuses(cDai);
        assertTrue(isPaused == isPaused_);
        assertTrue(isPartialPaused == isPartialPaused_);
        assertTrue(reserveFactor == marketsManager.reserveFactor(cDai));
    }

    function testGetUpdatedP2PExchangeRates() public {
        hevm.warp(block.timestamp + (365 days));
        marketsManager.updateP2PExchangeRates(cDai);

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = marketsManager
        .getUpdatedP2PExchangeRates(cDai);
        assertEq(newBorrowP2PExchangeRate, marketsManager.borrowP2PExchangeRate(cDai));
        assertEq(newSupplyP2PExchangeRate, marketsManager.supplyP2PExchangeRate(cDai));
    }
}
