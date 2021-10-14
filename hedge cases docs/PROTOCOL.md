# Keys to understand Morpho protocol

(A GitBook is being written and will be out soon)

Morpho moves credit lines in and out of AAVE/Compound to match users in Peer-to-Peer, thus improving capital-efficiency and liquidity whilst preserving the same market risks.

A user can trigger five different functions: supply, withdraw, borrow, repay and liquidate. Here we give an informal description of how each of those functions work.

Each function consider many different cases depending on the liquidity state of Morpho. In practice, most functions that will effectively happen on Morpho are gas efficient. However, one may remark that absolutely extreme scenarios like Withdraw 2.2.2 can be more costly. Such scenarios are totally unlikely but they are still implemented to ensure that Morpho can handle extreme liquidity states.

## A user supplies tokens ([`supply`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CreamPositionsManager.sol#L210))

#### CASE 1: Some borrowers are waiting on Cream, Morpho matches the supplier in P2P with them

- Morpho moves the borrowers from Cream to P2P
- Morpho updates the P2P supply balance of the user

##### If there aren't enough borrowers waiting on Cream to match all the tokens supplied

- Morpho supplies the tokens to Cream
- Morpho updates the Cream supply balance of the user

#### CASE 2: There aren't any borrowers waiting on Cream, Morpho supplies all the tokens to Cream

- Morpho updates the Cream supply balance of the user
- Morpho supplies the tokens to Cream

## A user borrows tokens ([`borrow`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CreamPositionsManager.sol#L251))

#### CASE 1: Some suppliers are waiting on Cream, Morpho matches the borrowers in P2P with them

- Morpho moves the suppliers from Cream to P2P
- Morpho updates the P2P borrow balance of the user

##### If there aren't enough suppliers waiting on Cream to match all the tokens borrowed

- Morpho moves all the supply of the user from P2P to Cream to ensure Morpho's borrow is going to be backed with collateral.
- Morpho borrows the tokens from Cream.
- Morpho updates the Cream borrow balance of the user.

#### CASE 2: There aren't any borrowers waiting on Cream, Morpho borrows all the tokens from Cream

- Morpho moves the supply of the user from P2P to Cream to ensure Morpho's borrow is going to be backed with collateral.
- Morpho borrows the tokens from Cream.
- Morpho updates the Cream borrow balance of the user.

## A user withdraws tokens ([`_withdraw`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CreamPositionsManager.sol#L462))

#### If user has some tokens waiting on Cream

##### CASE 1: User withdraws less than his Cream supply balance

- Morpho withdraws the tokens from Cream.
- Morpho updates the Cream supply balance of the user.

##### CASE 2: User withdraws more than his Cream supply balance

- Morpho withdraws all users' tokens on Cream.
- Morpho sets the Cream supply balance of the user to 0.

#### If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Cream itself

##### CASE 1: Other suppliers have enough tokens on Cream to compensate user's position

- Morpho moves those suppliers out of Cream to match the borrower that previously was in P2P with the user. (repairing credit lines with other users)
- Morpho updates the P2P supply balance of the user.

##### CASE 2: Other suppliers don't have enough tokens on Cream. Such scenario is called the Hard-Withdraw

- Morpho moves all the suppliers from Cream to P2P. (repairing credit lines with other users)
- Morpho moves borrowers that are in P2P back to Cream. (repairing credit lines with Cream itself)
- Morpho updates the P2P supply balance of the user.

- Morpho sends the tokens to the user

## A user repays tokens ([`_repay`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CreamPositionsManager.sol#L393))

#### If user is borrowing tokens on Cream

##### CASE 1: User repays less than his Cream borrow balance

- Morpho supplies the tokens to Cream.
- Morpho updates the Cream borrow balance of the user.

##### CASE 2: User repays more than his Cream borrow balance

- Morpho supplies all the tokens to Cream.
- Morpho sets the Cream borrow balance of the user to 0.

#### If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Cream itself

##### CASE 1: Other borrowers are borrowing enough on Cream to compensate user's position

- Morpho moves those borrowers out of Cream to match the supplier that was in P2P with the user.
- Morpho supplies the tokens to Cream.
- Morpho updates the P2P borrow balance of the user.

##### CASE 2: Other borrowers aren't borrowing enough on Cream to compensate user's position

- Morpho moves all the borrowers from Cream to P2P. (repairing credit lines with other users)
- Morpho moves suppliers that are in P2P back to Cream. (repairing credit lines with Cream itself)
- Morpho updates the P2P borrow balance of the user.

### Alice liquidates the borrow position of Bob ([`liquidate`](https://github.com/morpho-labs/morpho-contracts/blob/b4b8ddd4fcebf3a4d497a5518d8155514040a3dc/contracts/CreamPositionsManager.sol#L323))

- Alice repays the position of Bob: Morpho reuses the logic repay function mentioned before
- Morpho calculates the amount of colalteral to seize
- Alice siezes the collateral of Bob: Morpho reuses the logic of the withdraw mentioned before

---

### The Morpho Liquidation invariant

In order to ensure that Morpho does not bring any additional market risk, we have to limit the liquidation of the Morpho Contract itself by Cream liquidators

Indeed, such liquidation should only happen if every single user of Morpho has already been liquidated. Thus we must maintain the following invariant; Morpho's contract is liquidable only if every Morpho's users are all liquidable/liquidated.

To maintain this invariant, we remark that every single borrow position on Cream of a user should be effectively backed by the corresponding collateral. In other words, a collateral of a borrow position on Cream can't be matched. This is why:

- In the \_moveBorrowersFromP2PToCream(), we first use \_moveSupplierFromCompound to ensure that the collateral is put on Cream before borrowing on Cream.
- When using moveSuppliersFromCreamToP2P(), we always check if the user is actually borrowing something on Cream. If yes, we don't move the supply in P2P to ensure that this collateral remains on Cream.

### Hard-Withdraw

Reconnecting a credit line with Cream in a withdraw is no easy task. The intuition is that borrowers left with the money of a supplier, and this latter wants to withdraw his funds. A nice trick is to use the collateral of those borrowers so that Morpho does an actual borrow on Cream. This way the borrowers are now borrowing on Cream and the supplier is refunded!

However we have to distinguish two cases:

#### The collateral of the borrower is on Cream

Here, it is quite simple, Morpho can safely borrow

#### The collateral of the borrower is matched

In that scenario, which is extremely rare, Morpho can't borrow thanks to the colalteral as it is not being supplied to Cream. The trick is thus to recursively try to borrow on the collateral of the borrower that is matching the collateral. In the following example, we give an intuition of the proof of termination of this recursive loop, which is bounded to N-1, where N is yhe number of markets in the protocol.

Let's consider the most extreme scenario where Alice, Bob, Charlie and David are matched in P2P with collateral factors of 100%. This is handled by Morpho even though in practice, this very very unlikely and gas expensive. This can also be triggered by a hardworker. Find the document Hard-withdraw-with-matched-collateral.pdf to go through this example.
