## 1. [`SUPPLY`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L290)

- 1.1 - There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.

- 1.2 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.

- 1.3 - There is 1 available borrower, he doesn't match 100% of the supplier liquidity. Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.

- 1.4 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.

- 1.5 - The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`. ⚠️ most gas expensive supply scenario.

## 2. [`BORROW`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L361)

- 2.1 - The borrower tries to borrow more than his collateral allows (also taking in account pre existing borrow positions), the transaction reverts.

- 2.2 - There are no available suppliers: all of the borrowed amount is `onPool`.

- 2.3 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is `inP2P`.

- 2.4 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity. Borrower `inP2P` is equal to the supplier previous amount `onPool`, the rest is set `onPool`.

- 2.5 - There are NMAX (or less) supplier that match the borrowed amount, everything is `inP2P` after NMAX (or less) match.

- 2.6 - The NMAX biggest supplier don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set `onPool`. ⚠️ most gas expensive borrow scenario.

## 3. [`WITHDRAW`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L534)

- 3.1 - The user withdrawal leads to an under-collateralized position, the withdrawal reverts.

- 3.2 - The supplier withdraws less than his `onPool` balance. The liquidity is taken from his `onPool` balance.

- 3.3 - The supplier withdraws more than his `onPool` balance.
  - 3.3.1 - There is a supplier `onPool` available to replace him `inP2P`. First, his liquidity `onPool` is taken, his matched is replaced by the available supplier up to his withdrawal amount.
  - 3.3.2 - There are NMAX (or less) suppliers `onPool` available to replace him `inP2P`, they supply enough to cover for the withdrawn liquidity. First, his liquidity `onPool` is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
  - 3.3.3 - There are no suppliers `onPool` to replace him `inP2P`. After withdrawing the amount `onPool`, his P2P match(es) will be unmatched and the corresponding borrower(s) will be placed on pool.
  - 3.3.4 - The supplier is matched to 2\*NMAX borrowers. There are NMAX suppliers `onPool` available to replace him `inP2P`, they don't supply enough to cover the withdrawn liquidity. First, the `onPool` liquidity is withdrawn, then we proceed to NMAX `match supplier`. Finally, we proceed to NMAX `unmatch borrower` for an amount equal to the remaining to withdraw. ⚠️ most gas expensive withdraw scenario.

## 4. [`REPAY`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L642)

- 4.1 - The borrower repays less than his `onPool` balance. The liquidity is repaid on his `onPool` balance.

- 4.2 - The borrower repays more than his `onPool` balance.
  - 4.2.1 - There is a borrower `onPool` available to replace him `inP2P`. First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
  - 4.2.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity. First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
  - 4.2.3 - There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`, his P2P match(es) will be unmatched and the corresponding supplier(s) will be placed on pool.
  - 4.2.4 - The borrower is matched to 2\*NMAX suppliers. There are NMAX borrowers `onPool` available to replace him `inP2P`, they don't supply enough to cover for the repaid liquidity. First, the `onPool` liquidity is repaid, then we proceed to NMAX `match borrower`. Finally, we proceed to NMAX `unmatch supplier` for an amount equal to the remaining to withdraw. ⚠️ most gas expensive repay scenario.

## 5. [`LIQUIDATE`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L452)

- 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.

- 5.2 - A user liquidates a borrower that has not enough collateral to cover for his debt.
