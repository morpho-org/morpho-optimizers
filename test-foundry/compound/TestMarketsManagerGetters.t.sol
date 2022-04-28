// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRatesGetters is TestSetup {
    function testGetAllMarkets() public {
        address[] memory allMarkets = morpho.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }

    function testGetMarketData() public {
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        ) = morpho.getMarketData(cDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(cDai));
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(cDai));
        (uint32 expectedLastUpdateBlockNumber, , ) = morpho.lastPoolIndexes(cDai);
        assertEq(lastUpdateBlockNumber, expectedLastUpdateBlockNumber);
        (
            uint256 supplyP2PDelta,
            uint256 borrowP2PDelta,
            uint256 supplyP2PAmount,
            uint256 borrowP2PAmount
        ) = morpho.deltas(cDai);

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
            bool isPartiallyPaused,
            uint256 reserveFactor
        ) = morpho.getMarketConfiguration(cDai);

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatuses(cDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(noP2P == morpho.noP2P(cDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, ) = morpho.marketParameters(cDai);
        assertTrue(reserveFactor == expectedReserveFactor);
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.warp(block.timestamp + (365 days));
        morpho.updateP2PIndexes(cDai);

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = morpho.getUpdatedP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }
}
