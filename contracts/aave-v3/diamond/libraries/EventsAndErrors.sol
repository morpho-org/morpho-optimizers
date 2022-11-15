// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {Types} from "./Libraries.sol";

library EventsAndErrors {
    /// @notice Emitted when a supply happens.
    /// @param _from The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _poolToken The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Supplied(
        address indexed _from,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update
    event Borrowed(
        address indexed _borrower,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a withdrawal happens.
    /// @param _supplier The address of the supplier whose supply is withdrawn.
    /// @param _receiver The address receiving the tokens.
    /// @param _poolToken The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Withdrawn(
        address indexed _supplier,
        address indexed _receiver,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a repayment happens.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _poolToken The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event Repaid(
        address indexed _repayer,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidated The address of the liquidated.
    /// @param _poolTokenBorrowed The address of the borrowed asset.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenCollateral The address of the collateral asset seized.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    event Liquidated(
        address _liquidator,
        address indexed _liquidated,
        address indexed _poolTokenBorrowed,
        uint256 _amountRepaid,
        address indexed _poolTokenCollateral,
        uint256 _amountSeized
    );

    /// @notice Emitted when the peer-to-peer deltas are increased by the governance.
    /// @param _poolToken The address of the market on which the deltas were increased.
    /// @param _amount The amount that has been added to the deltas (in underlying).
    event P2PDeltasIncreased(address indexed _poolToken, uint256 _amount);

    /// @notice Emitted when the peer-to-peer indexes of a market are updated.
    /// @param _poolToken The address of the market updated.
    /// @param _p2pSupplyIndex The updated supply index from peer-to-peer unit to underlying.
    /// @param _p2pBorrowIndex The updated borrow index from peer-to-peer unit to underlying.
    /// @param _poolSupplyIndex The updated pool supply index.
    /// @param _poolBorrowIndex The updated pool borrow index.
    event P2PIndexesUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyIndex,
        uint256 _p2pBorrowIndex,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex
    );

    /// @notice Emitted when a new `defaultMaxGasForMatching` is set.
    /// @param _defaultMaxGasForMatching The new `defaultMaxGasForMatching`.
    event DefaultMaxGasForMatchingSet(Types.MaxGasForMatching _defaultMaxGasForMatching);

    /// @notice Emitted when a new value for `maxSortedUsers` is set.
    /// @param _newValue The new value of `maxSortedUsers`.
    event MaxSortedUsersSet(uint256 _newValue);

    /// @notice Emitted when the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address indexed _newTreasuryVaultAddress);

    /// @notice Emitted when the address of the `incentivesVault` is set.
    /// @param _newIncentivesVaultAddress The new address of the `incentivesVault`.
    event IncentivesVaultSet(address indexed _newIncentivesVaultAddress);

    /// @notice Emitted when the `entryPositionsManager` is set.
    /// @param _entryPositionsManager The new address of the `entryPositionsManager`.
    event EntryPositionsManagerSet(address indexed _entryPositionsManager);

    /// @notice Emitted when the `exitPositionsManager` is set.
    /// @param _exitPositionsManager The new address of the `exitPositionsManager`.
    event ExitPositionsManagerSet(address indexed _exitPositionsManager);

    /// @notice Emitted when the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address indexed _newRewardsManagerAddress);

    /// @notice Emitted when the `interestRatesManager` is set.
    /// @param _interestRatesManager The new address of the `interestRatesManager`.
    event InterestRatesSet(address indexed _interestRatesManager);

    /// @notice Emitted when the address of the `rewardsController` is set.
    /// @param _rewardsController The new address of the `rewardsController`.
    event RewardsControllerSet(address indexed _rewardsController);

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolToken The address of the concerned market.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolToken, uint16 _newValue);

    /// @notice Emitted when the `p2pIndexCursor` is set.
    /// @param _poolToken The address of the concerned market.
    /// @param _newValue The new value of the `p2pIndexCursor`.
    event P2PIndexCursorSet(address indexed _poolToken, uint16 _newValue);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolToken The address of the concerned market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address indexed _poolToken, uint256 _amountClaimed);

    /// @notice Emitted when the value of `isP2PDisabled` is set.
    /// @param _poolToken The address of the concerned market.
    /// @param _isP2PDisabled The new value of `_isP2PDisabled` adopted.
    event IsP2PDisabledSet(address indexed _poolToken, bool _isP2PDisabled);

    /// @notice Emitted when supplying is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsSupplyPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when borrowing is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsBorrowPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when withdrawing is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsWithdrawPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when repaying is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsRepayPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when liquidating on this market as collateral is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsLiquidateCollateralPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when liquidating on this market as borrow is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _isPaused The new pause status of the market.
    event IsLiquidateBorrowPausedSet(address indexed _poolToken, bool _isPaused);

    /// @notice Emitted when a market is set as deprecated or not.
    /// @param _poolToken The address of the concerned market.
    /// @param _isDeprecated The new deprecated status.
    event IsDeprecatedSet(address indexed _poolToken, bool _isDeprecated);

    /// @notice Emitted when claiming rewards is paused or unpaused.
    /// @param _isPaused The new pause status.
    event IsClaimRewardsPausedSet(bool _isPaused);

    /// @notice Emitted when a new market is created.
    /// @param _poolToken The address of the market that has been created.
    /// @param _reserveFactor The reserve factor set for this market.
    /// @param _poolToken The P2P index cursor set for this market.
    event MarketCreated(address indexed _poolToken, uint16 _reserveFactor, uint16 _p2pIndexCursor);

    /// @notice Emitted when the peer-to-peer borrow delta is updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pBorrowDelta The peer-to-peer borrow delta after update.
    event P2PBorrowDeltaUpdated(address indexed _poolToken, uint256 _p2pBorrowDelta);

    /// @notice Emitted when the peer-to-peer supply delta is updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pSupplyDelta The peer-to-peer supply delta after update.
    event P2PSupplyDeltaUpdated(address indexed _poolToken, uint256 _p2pSupplyDelta);

    /// @notice Emitted when the supply and peer-to-peer borrow amounts are updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pSupplyAmount The peer-to-peer supply amount after update.
    /// @param _p2pBorrowAmount The peer-to-peer borrow amount after update.
    event P2PAmountsUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyAmount,
        uint256 _p2pBorrowAmount
    );

    /// ERRORS ///

    /// @notice Thrown when borrowing is impossible, because it is not enabled on pool for this specific market.
    error BorrowingNotEnabled();

    /// @notice Thrown when the user does not have enough collateral for the borrow.
    error UnauthorisedBorrow();

    /// @notice Thrown when someone tries to supply but the supply is paused.
    error SupplyIsPaused();

    /// @notice Thrown when someone tries to borrow but the borrow is paused.
    error BorrowIsPaused();

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the user does not have enough remaining collateral to withdraw.
    error UnauthorisedWithdraw();

    /// @notice Thrown when the positions of the user is not liquidatable.
    error UnauthorisedLiquidate();

    /// @notice Thrown when someone tries to withdraw but the withdraw is paused.
    error WithdrawIsPaused();

    /// @notice Thrown when someone tries to repay but the repay is paused.
    error RepayIsPaused();

    /// @notice Thrown when someone tries to liquidate but the liquidation with this asset as collateral is paused.
    error LiquidateCollateralIsPaused();

    /// @notice Thrown when someone tries to liquidate but the liquidation with this asset as debt is paused.
    error LiquidateBorrowIsPaused();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the input is above the max basis points value (100%).
    error ExceedsMaxBasisPoints();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when trying to set the max sorted users to 0.
    error MaxSortedUsersCannotBeZero();

    /// @notice Thrown when the number of markets will exceed the bitmask's capacity.
    error MaxNumberOfMarkets();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the address is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();
}
