// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./MorphoGetters.sol";

/// @title MorphoEventsErrors.
/// @notice Events and Errors for Morpho.
abstract contract MorphoEventsErrors is MorphoGetters {
    /// EVENTS ///

    /// @notice Emitted when a supply happens.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event Supplied(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a withdrawal happens.
    /// @param _user The address of the withdrawer.
    /// @param _poolTokenAddress The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event Withdrawn(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update
    event Borrowed(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a repayment happens.
    /// @param _user The address of the repayer.
    /// @param _poolTokenAddress The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event Repaid(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidated The address of the liquidated.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenBorrowedAddress The address of the borrowed asset.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    /// @param _poolTokenCollateralAddress The address of the collateral asset seized.
    event Liquidated(
        address _liquidator,
        address indexed _liquidated,
        uint256 _amountRepaid,
        address indexed _poolTokenBorrowedAddress,
        uint256 _amountSeized,
        address indexed _poolTokenCollateralAddress
    );

    /// EVENTS ///

    /// @notice Emitted when a new `maxGasForMatching` is set.
    /// @param _maxGasForMatching The new `maxGasForMatching`.
    event MaxGasForMatchingSet(Types.MaxGasForMatching _maxGasForMatching);

    /// @notice Emitted when a new value for `maxSortedUsers` is set.
    /// @param _newValue The new value of `maxSortedUsers`.
    event MaxSortedUsersSet(uint256 _newValue);

    /// @notice Emitted the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address indexed _newTreasuryVaultAddress);

    /// @notice Emitted the address of the `incentivesVault` is set.
    /// @param _newIncentivesVaultAddress The new address of the `incentivesVault`.
    event IncentivesVaultSet(address indexed _newIncentivesVaultAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The new address of the `positionsManager`.
    event PositionsManagerSet(address indexed _positionsManager);

    /// @notice Emitted when the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address indexed _newRewardsManagerAddress);

    /// @notice Emitted when the `interestRates` is set.
    /// @param _interestRates The new address of the `interestRates`.
    event InterestRatesSet(address indexed _interestRates);

    /// @dev Emitted when a new `dustThreshold` is set.
    /// @param _dustThreshold The new `dustThreshold`.
    event DustThresholdSet(uint256 _dustThreshold);

    /// @notice Emitted when the value of `noP2P` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address indexed _poolTokenAddress, bool _noP2P);

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// @notice Emitted when the `p2pIndexCursor` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newValue The new value of the `p2pIndexCursor`.
    event P2PIndexCursorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address indexed _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a COMP reward status is changed.
    /// @param _isCompRewardsActive The new COMP reward status.
    event CompRewardsActive(bool _isCompRewardsActive);

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address indexed _user, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards and trades them for MORPHO tokens.
    /// @param _user The address of the claimer.
    /// @param _amountSent The amount of reward token sent to the vault.
    event RewardsClaimedAndTraded(address indexed _user, uint256 _amountSent);

    /// @notice Emitted when a market is paused or unpaused.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event PauseStatusChanged(address indexed _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when a market is partially paused or unpaused.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newStatus The new partial pause status of the market.
    event PartialPauseStatusChanged(address indexed _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when a new market is created.
    /// @param _poolTokenAddress The address of the market that has been created.
    event MarketCreated(address _poolTokenAddress);

    /// ERRORS ///

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();
}
