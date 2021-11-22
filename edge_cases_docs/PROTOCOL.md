# Keys to understand Morpho protocol

(A GitBook is being written and will be out soon)

Morpho moves credit lines in and out of AAVE/Compound to match users in Peer-to-Peer, thus improving capital-efficiency and liquidity whilst preserving the same market risks.

A user can trigger five different functions: supply, withdraw, borrow, repay and liquidate. Here we give an informal description of how each of those functions work.

Each function considers many different cases depending on the liquidity state of Morpho. In practice, most functions that will effectively happen on Morpho are gas efficient. However, one may remark that absolutely extreme scenarios like Withdraw 2.2.2 can be more costly. Such scenarios are totally unlikely but they are still implemented to ensure that Morpho can handle extreme liquidity states.

## A user supplies tokens ([`supply`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CompoundPositionsManager.sol#L210))

#### CASE 1: Some borrowers are waiting on Compound, Morpho matches the supplier in P2P with them

- Morpho moves the borrowers from Compound to P2P
- Morpho updates the P2P supply balance of the user

##### If there aren't enough borrowers waiting on Compound to match all the tokens supplied

- Morpho supplies the tokens to Compound
- Morpho updates the Compound supply balance of the user

#### CASE 2: There aren't any borrowers waiting on Compound, Morpho supplies all the tokens to Compound

- Morpho updates the Compound supply balance of the user
- Morpho supplies the tokens to Compound

## A user borrows tokens ([`borrow`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CompoundPositionsManager.sol#L251))

#### CASE 1: Some suppliers are waiting on Compound, Morpho matches the borrowers in P2P with them

- Morpho moves the suppliers from Compound to P2P
- Morpho updates the P2P borrow balance of the user

##### If there aren't enough suppliers waiting on Compound to match all the tokens borrowed

- Morpho moves all the supply of the user from P2P to Compound to ensure Morpho's borrow is going to be backed with collateral.
- Morpho borrows the tokens from Compound.
- Morpho updates the Compound borrow balance of the user.

#### CASE 2: There aren't any borrowers waiting on Compound, Morpho borrows all the tokens from Compound

- Morpho moves the supply of the user from P2P to Compound to ensure Morpho's borrow is going to be backed with collateral.
- Morpho borrows the tokens from Compound.
- Morpho updates the Compound borrow balance of the user.

## A user withdraws tokens ([`_withdraw`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CompoundPositionsManager.sol#L462))

#### If user has some tokens waiting on Compound

##### CASE 1: User withdraws less than his Compound supply balance

- Morpho withdraws the tokens from Compound.
- Morpho updates the Compound supply balance of the user.

##### CASE 2: User withdraws more than his Compound supply balance

- Morpho withdraws all users' tokens on Compound.
- Morpho sets the Compound supply balance of the user to 0.

#### If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Compound itself

##### CASE 1: Other suppliers have enough tokens on Compound to compensate user's position

- Morpho moves those suppliers out of Compound to match the borrower that previously was in P2P with the user. (repairing credit lines with other users)
- Morpho updates the P2P supply balance of the user.

##### CASE 2: Other suppliers don't have enough tokens on Compound. Such scenario is called the Hard-Withdraw

- Morpho moves all the suppliers from Compound to P2P. (repairing credit lines with other users)
- Morpho moves borrowers that are in P2P back to Compound. (repairing credit lines with Compound itself)
- Morpho updates the P2P supply balance of the user.

- Morpho sends the tokens to the user

## A user repays tokens ([`_repay`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CompoundPositionsManager.sol#L393))

#### If user is borrowing tokens on Compound

##### CASE 1: User repays less than his Compound borrow balance

- Morpho supplies the tokens to Compound.
- Morpho updates the Compound borrow balance of the user.

##### CASE 2: User repays more than his Compound borrow balance

- Morpho supplies all the tokens to Compound.
- Morpho sets the Compound borrow balance of the user to 0.

#### If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repairs them either with other users or with Compound itself

##### CASE 1: Other borrowers are borrowing enough on Compound to compensate user's position

- Morpho moves those borrowers out of Compound to match the supplier that was in P2P with the user.
- Morpho supplies the tokens to Compound.
- Morpho updates the P2P borrow balance of the user.

##### CASE 2: Other borrowers aren't borrowing enough on Compound to compensate user's position

- Morpho moves all the borrowers from Compound to P2P. (repairing credit lines with other users)
- Morpho moves suppliers that are in P2P back to Compound. (repairing credit lines with Compound itself)
- Morpho updates the P2P borrow balance of the user.

### Alice liquidates the borrow position of Bob ([`liquidate`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CompoundPositionsManager.sol#L323))

- Alice repays the position of Bob: Morpho reuses the logic repay function mentioned before.
- Morpho calculates the amount of collateral to seize.
- Alice siezes the collateral of Bob: Morpho reuses the logic of the withdraw mentioned before.

---

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

In that scenario, which is extremely rare, Morpho can safely perform the same operation.  This is proven in Morpho's Yellow paper. Please contact us if you want more information regarding this.
