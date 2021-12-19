# Keys to understand Morpho protocol

(A GitBook is being written and will be out soon)

Morpho moves credit lines in and out of AAVE/Compound to match users in Peer-to-Peer, thus improving capital-efficiency and liquidity whilst preserving the same market risks.

A user can trigger five different functions: supply, withdraw, borrow, repay and liquidate. Here we give an informal description of how each of those functions work.

Each function considers many different cases depending on the liquidity state of Morpho. In practice, most functions that will effectively happen on Morpho are gas efficient. However, one may remark that absolutely extreme scenarios like Withdraw 2.2.2 can be more costly. Such scenarios are totally unlikely but they are still implemented to ensure that Morpho can handle extreme liquidity states.

## 1. [`SUPPLY`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L290)

- 1.1 - There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.

- 1.2 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.

- 1.3 - There is 1 available borrower, he doesn't match 100% of the supplier liquidity. Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.

- 1.4 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.

- 1.5 - The NMAX bigger borrowers don't match all of the supplied amount, after NMAX match, the rest supplied and set `onPool`. ⚠️ most gaz expensive supply scenario.

## 2. [`BORROW`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L361)

- 2.1 - There are no available suppliers: all of the borrowed amount is `onPool`.

- 2.2 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is `inP2P`.

- 2.3 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity. Borrower `inP2P` is equal to the supplier previous amount `onPool`, the rest is set `onPool`.

- 2.4 - There are NMAX (or less) supplier that match the supplied amount, everything is `inP2P` after NMAX (or less) match.

- 2.5 - The NMAX bigger supplier don't match all of the borrowed amount, after NMAX match, the rest borrowed and set `onPool`. ⚠️ most gaz expensive borrow scenario.

## 3. [`WITHDRAW`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L534)

- 3.1 - The user withdrawal leads to an under-collateralized position, the withdrawal reverts.

- 3.2 - The supplier withdraws less than his `onPool` balance. The liquidity is taken from his `onPool` balance.

- 3.3 - The supplier withdraws more than his `onPool` balance.
  - 3.3.1 - There is a supplier `onPool` available to replace him `inP2P`. First, his liquidity `onPool` is taken, his matched is replaced by the available supplier up to his withdrawal amount.
  - 3.3.2 - There are NMAX (or less) suppliers `onPool` available to replace him `inP2P`, they supply enough to cover for the withdrawn liquidity. First, his liquidity `onPool` is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
  - 3.3.3 - There are no suppliers `onPool` to replace him `inP2P`. After withdrawing the amount `onPool`, his P2P match(s) will be unmatched and the corresponding borrower(s) will be placed on pool.
  - 3.3.4 - There are NMAX (or less) suppliers `onPool` available to replace him `inP2P`, they don't supply enough to cover for the withdrawn liquidity. First, the `onPool` liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some borrowers are unmatched for an amount equal to the remaining to withdraw. ⚠️ most gaz expensive withdraw scenario.

## 4. [`REPAY`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L642)

- 3.1 - The borrower repays less than his `onPool` balance. The liquidity is repaid on his `onPool` balance.

- 3.3 - The borrower repays more than his `onPool` balance.
  - 3.3.1 - There is a borrower `onPool` available to replace him `inP2P`. First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
  - 3.3.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity. First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
  - 3.3.3 - There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`, his P2P match(s) will be unmatched and the corresponding supplier(s) will be placed on pool.
  - 3.3.4 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they don't supply enough to cover for the withdrawn liquidity. First, the `onPool` liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some suppliers are unmatched for an amount equal to the remaining to withdraw. ⚠️ most gaz expensive repay scenario.

## 4. [`LIQUIDATE`](https://github.com/morpho-labs/morpho-contracts/blob/main/contracts/aave/PositionsManagerForAave.sol#L452)

- 4.1 - A user liquidate a borrower that has a health factor superior to 1, the transaction reverts.

- 4.2 - The liquidation is made of a Repay and Withdraw performed on a borrower's position on behalf of a liquidator. At most, the liquidator can liquidate 50% of the debt of a borrower and take the corresponding collateral. Edge-cases here are at most the combination from part 3. and 4. called with the previous amount.

### The Morpho Liquidation invariant

In order to ensure that Morpho does not bring any additional market risk, we have to limit the liquidation of the Morpho Contract itself by Compound liquidators.

Indeed, such liquidation should only happen if every single user of Morpho has already been liquidated. Thus we must maintain the following invariant; Morpho's contract is liquidable only if every Morpho's users are all liquidable/liquidated.

To maintain this invariant, we remark that every single borrow position on Compound of a user should be effectively backed by the corresponding collateral. In other words, a collateral of a borrow position on Compound can't be matched. This is why:

- In the `_unmatchBorrowers()`, we first use `_unmatchTheSupplier()` to ensure that the collateral is put on Compound before borrowing on Compound.
- When using `moveSuppliersFromCompoundToP2P()`, we always check if the user is actually borrowing something on Compound. If yes, we don't move the supply in P2P to ensure that this collateral remains on Compound.
- When using `borrow()`, when it come to borrowing on Compound we start by using `_unmatchTheSupplier()` to ensure that the collateral is put on Compound.

### Hard-Withdraw

Reconnecting a credit line with Compound in a withdraw is no easy task. The intuition is that borrowers left with the money of a supplier, and this latter wants to withdraw his funds. A nice trick is to use the collateral of those borrowers so that Morpho does an actual borrow on Compound. This way the borrowers are now borrowing on Compound and the supplier is refunded!

However we have to distinguish two cases:

#### The collateral of the borrower is on Compound

Here, it is quite simple, Morpho can safely borrow.

#### The collateral of the borrower is matched

In that scenario, which is extremely rare, Morpho can safely perform the same operation. This is proven in Morpho's Yellow paper. Please contact us if you want more information regarding this.
