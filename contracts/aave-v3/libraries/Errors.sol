// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library Errors {
    /// @notice Thrown when claiming rewards is paused.
    error ClaimRewardsPaused();

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

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the address is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();
}
