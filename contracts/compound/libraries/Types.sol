// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library Types {
    struct Params {
        uint256 supplyP2PExchangeRate; // The current supply P2P exchange rate.
        uint256 borrowP2PExchangeRate; // The current borrow P2P exchange rate
        uint256 poolSupplyExchangeRate; // The current pool supply exchange rate
        uint256 poolBorrowExchangeRate; // The pool supply exchange rate at last update.
        uint256 lastPoolSupplyExchangeRate; // The pool borrow exchange rate at last update.
        uint256 lastPoolBorrowExchangeRate; // The pool borrow exchange rate at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        Delta delta; // The deltas and P2P amounts.
    }

    struct Delta {
        uint256 supplyP2PDelta; // Difference between the stored P2P supply amount and the real P2P supply amount (in scaled balance).
        uint256 borrowP2PDelta; // Difference between the stored P2P borrow amount and the real P2P borrow amount (in adUnit).
        uint256 supplyP2PAmount; // Sum of all stored P2P supply (in P2P unit).
        uint256 borrowP2PAmount; // Sum of all stored P2P borrow (in P2P unit).
    }
}
