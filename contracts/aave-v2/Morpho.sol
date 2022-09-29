// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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

    /// ERRORS ///

    /// @notice Thrown when claiming rewards is paused.
    error ClaimRewardsPaused();

    /// EXTERNAL ///

    /// @notice Supplies underlying tokens to a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(address _poolToken, uint256 _amount) external nonReentrant {
        _supply(_poolToken, msg.sender, _amount, defaultMaxGasForMatching.supply);
    }

    /// @notice Supplies underlying tokens to a specific market, on behalf of a given user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) external nonReentrant {
        _supply(_poolToken, _onBehalf, _amount, defaultMaxGasForMatching.supply);
    }

    /// @notice Supplies underlying tokens to a specific market, specifying a gas threshold at which to cut the matching engine.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasForMatching The gas threshold at which to stop the matching engine.
    function supply(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant {
        _supply(_poolToken, msg.sender, _amount, _maxGasForMatching);
    }

    /// @notice Supplies underlying tokens to a specific market, on behalf of a given user,
    ///         specifying a gas threshold at which to cut the matching engine.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasForMatching The gas threshold at which to stop the matching engine.
    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant {
        _supply(_poolToken, _onBehalf, _amount, _maxGasForMatching);
    }

    /// @notice Borrows underlying tokens from a specific market.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function borrow(address _poolToken, uint256 _amount) external nonReentrant {
        _borrow(_poolToken, msg.sender, _amount, defaultMaxGasForMatching.borrow);
    }

    /// @notice Borrows underlying tokens from a specific market and sends them to a given address.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _receiver The address to send borrowed tokens to.
    function borrow(
        address _poolToken,
        address _receiver,
        uint256 _amount
    ) external nonReentrant {
        _borrow(_poolToken, _receiver, _amount, defaultMaxGasForMatching.borrow);
    }

    /// @notice Borrows underlying tokens from a specific market, specifying a gas threshold at which to stop the matching engine.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The gas threshold at which to stop the matching engine.
    function borrow(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant {
        _borrow(_poolToken, msg.sender, _amount, _maxGasForMatching);
    }

    /// @notice Borrows underlying tokens from a specific market and sends them to a given address,
    ///         specifying a maximum amount of gas used by the matching engine (not strict).
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _receiver The address to send borrowed tokens to.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolToken,
        address _receiver,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant {
        _borrow(_poolToken, _receiver, _amount, _maxGasForMatching);
    }

    /// @notice Withdraws underlying tokens from a specific market.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolToken, uint256 _amount)
        external
        nonReentrant
        returns (uint256 withdrawn)
    {
        return _withdraw(_poolToken, msg.sender, _amount, defaultMaxGasForMatching.withdraw);
    }

    /// @notice Withdraws underlying tokens from a specific market.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    /// @param _receiver The address to send withdrawn tokens to.
    function withdraw(
        address _poolToken,
        address _receiver,
        uint256 _amount
    ) external nonReentrant returns (uint256 withdrawn) {
        return _withdraw(_poolToken, _receiver, _amount, defaultMaxGasForMatching.withdraw);
    }

    /// @notice Repays the debt of the sender, up to the amount provided.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolToken, uint256 _amount)
        external
        nonReentrant
        returns (uint256 repaid)
    {
        return _repay(_poolToken, msg.sender, _amount, defaultMaxGasForMatching.repay);
    }

    /// @notice Repays debt of a given user, up to the amount provided.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) external nonReentrant returns (uint256 repaid) {
        return _repay(_poolToken, _onBehalf, _amount, defaultMaxGasForMatching.repay);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowed The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateral The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external nonReentrant returns (uint256 seized) {
        return _liquidate(_poolTokenBorrowed, _poolTokenCollateral, _borrower, msg.sender, _amount);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowed The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateral The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _receiver The address of the receiver of the seized collateral.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        address _receiver,
        uint256 _amount
    ) external nonReentrant returns (uint256 seized) {
        return _liquidate(_poolTokenBorrowed, _poolTokenCollateral, _borrower, _receiver, _amount);
    }

    /// @notice Claims rewards for the given assets.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _tradeForMorphoToken Whether or not to trade reward tokens for MORPHO tokens.
    /// @return claimedAmount The amount of rewards claimed (in reward token).
    function claimRewards(address[] calldata _assets, bool _tradeForMorphoToken)
        external
        nonReentrant
        returns (uint256 claimedAmount)
    {
        return _claimRewards(_assets, _tradeForMorphoToken, msg.sender);
    }

    /// @notice Claims rewards for the given assets and sends them to `_receiver`.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _tradeForMorphoToken Whether or not to trade reward tokens for MORPHO tokens.
    /// @param _receiver The address to send reward tokens to.
    /// @return claimedAmount The amount of rewards claimed (in reward token).
    function claimRewards(
        address[] calldata _assets,
        bool _tradeForMorphoToken,
        address _receiver
    ) external nonReentrant returns (uint256 claimedAmount) {
        return _claimRewards(_assets, _tradeForMorphoToken, _receiver);
    }

    /// INTERNAL ///

    function _supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IEntryPositionsManager.supplyLogic.selector,
                _poolToken,
                msg.sender,
                _onBehalf,
                _amount,
                _maxGasForMatching
            )
        );
    }

    function _borrow(
        address _poolToken,
        address _receiver,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        address(entryPositionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IEntryPositionsManager.borrowLogic.selector,
                _poolToken,
                _amount,
                _receiver,
                _maxGasForMatching
            )
        );
    }

    function _withdraw(
        address _poolToken,
        address _receiver,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 withdrawn) {
        return
            abi.decode(
                address(exitPositionsManager).functionDelegateCall(
                    abi.encodeWithSelector(
                        IExitPositionsManager.withdrawLogic.selector,
                        _poolToken,
                        _amount,
                        msg.sender,
                        _receiver,
                        _maxGasForMatching
                    )
                ),
                (uint256)
            );
    }

    function _repay(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 repaid) {
        return
            abi.decode(
                address(exitPositionsManager).functionDelegateCall(
                    abi.encodeWithSelector(
                        IExitPositionsManager.repayLogic.selector,
                        _poolToken,
                        msg.sender,
                        _onBehalf,
                        _amount,
                        _maxGasForMatching
                    )
                ),
                (uint256)
            );
    }

    function _liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        address _receiver,
        uint256 _amount
    ) internal returns (uint256 seized) {
        return
            abi.decode(
                address(exitPositionsManager).functionDelegateCall(
                    abi.encodeWithSelector(
                        IExitPositionsManager.liquidateLogic.selector,
                        _poolTokenBorrowed,
                        _poolTokenCollateral,
                        _borrower,
                        _receiver,
                        _amount
                    )
                ),
                (uint256)
            );
    }

    function _claimRewards(
        address[] calldata _assets,
        bool _tradeForMorphoToken,
        address _receiver
    ) internal returns (uint256 claimedAmount) {
        if (isClaimRewardsPaused) revert ClaimRewardsPaused();
        claimedAmount = rewardsManager.claimRewards(aaveIncentivesController, _assets, msg.sender);

        if (claimedAmount > 0) {
            if (_tradeForMorphoToken) {
                aaveIncentivesController.claimRewards(
                    _assets,
                    claimedAmount,
                    address(incentivesVault)
                );
                incentivesVault.tradeRewardTokensForMorphoTokens(_receiver, claimedAmount);
            } else aaveIncentivesController.claimRewards(_assets, claimedAmount, _receiver);

            emit RewardsClaimed(msg.sender, claimedAmount, _tradeForMorphoToken);
        }
    }
}
