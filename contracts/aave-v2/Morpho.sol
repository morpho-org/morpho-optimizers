// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./MorphoGovernance.sol";

/// @title Morpho.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Main Morpho contract handling user interactions and pool interactions.
contract Morpho is MorphoGovernance {
    using SafeTransferLib for ERC20;
    using DelegateCall for address;
    using WadRayMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    /// @param _traded Whether or not the pool tokens are traded against Morpho tokens.
    event RewardsClaimed(address indexed _user, uint256 _amountClaimed, bool indexed _traded);

    /// ERRRORS ///

    /// @notice Thrown when the claim rewards is paused.
    error ClaimRewardsPaused();

    /// EXTERNAL ///

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(
        address _poolTokenAddress,
        address _onBehalf,
        uint256 _amount
    ) external nonReentrant isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress) {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                entryPositionsManager.supplyLogic.selector,
                _poolTokenAddress,
                msg.sender,
                _onBehalf,
                _amount,
                defaultMaxGasForMatching.supply
            )
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress) {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                entryPositionsManager.supplyLogic.selector,
                _poolTokenAddress,
                msg.sender,
                _onBehalf,
                _amount,
                _maxGasForMatching
            )
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function borrow(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress)
    {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                entryPositionsManager.borrowLogic.selector,
                _poolTokenAddress,
                _amount,
                defaultMaxGasForMatching.borrow
            )
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress) {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                entryPositionsManager.borrowLogic.selector,
                _poolTokenAddress,
                _amount,
                _maxGasForMatching
            )
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        address(exitPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                exitPositionsManager.withdrawLogic.selector,
                _poolTokenAddress,
                _amount,
                msg.sender,
                msg.sender,
                defaultMaxGasForMatching.withdraw
            )
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(
        address _poolTokenAddress,
        address _onBehalf,
        uint256 _amount
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        address(exitPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                exitPositionsManager.repayLogic.selector,
                _poolTokenAddress,
                msg.sender,
                _onBehalf,
                _amount,
                defaultMaxGasForMatching.repay
            )
        );
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    )
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenBorrowedAddress)
        isMarketCreatedAndNotPaused(_poolTokenCollateralAddress)
    {
        address(exitPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                exitPositionsManager.liquidateLogic.selector,
                _poolTokenBorrowedAddress,
                _poolTokenCollateralAddress,
                _borrower,
                _amount
            )
        );
    }

    /// @notice Claims rewards for the given assets.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _tradeForMorphoToken Whether or not to trade reward tokens for MORPHO tokens.
    function claimRewards(address[] calldata _assets, bool _tradeForMorphoToken)
        external
        nonReentrant
    {
        if (isClaimRewardsPaused) revert ClaimRewardsPaused();
        uint256 amountOfRewards = rewardsManager.claimRewards(_assets, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();

        if (_tradeForMorphoToken) {
            ERC20 rewardToken = ERC20(aaveIncentivesController.REWARD_TOKEN());

            aaveIncentivesController.claimRewards(_assets, amountOfRewards, address(this));
            rewardToken.safeApprove(address(incentivesVault), amountOfRewards);
            incentivesVault.tradeRewardTokensForMorphoTokens(msg.sender, amountOfRewards);
        } else aaveIncentivesController.claimRewards(_assets, amountOfRewards, msg.sender);

        emit RewardsClaimed(msg.sender, amountOfRewards, _tradeForMorphoToken);
    }
}
