// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library Types {
    struct Params {
        uint256 supplyP2PExchangeRate;
        uint256 borrowP2PExchangeRate;
        uint256 poolSupplyExchangeRate;
        uint256 poolBorrowExchangeRate;
        uint256 lastPoolSupplyExchangeRate;
        uint256 lastPoolBorrowExchangeRate;
        uint256 reserveFactor;
        Delta delta;
    }

    struct Delta {
        uint256 supplyP2PDelta; // Difference between the stored P2P supply amount and the real P2P supply amount (in scaled balance).
        uint256 borrowP2PDelta; // Difference between the stored P2P borrow amount and the real P2P borrow amount (in adUnit).
        uint256 supplyP2PAmount; // Sum of all stored P2P supply (in P2P unit).
        uint256 borrowP2PAmount; // Sum of all stored P2P borrow (in P2P unit).
    }
}
