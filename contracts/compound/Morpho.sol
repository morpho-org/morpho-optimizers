// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./libraries/DelegateCall.sol";

import "./MorphoGovernance.sol";

/// @title Morpho.
/// @notice Main Morpho contract handling user interactions and pool interactions.
contract Morpho is MorphoGovernance {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;
    using DelegateCall for address;

    /// EVENTS ///

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address indexed _user, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards and trades them for MORPHO tokens.
    /// @param _user The address of the claimer.
    /// @param _amountSent The amount of reward token sent to the vault.
    event RewardsClaimedAndTraded(address indexed _user, uint256 _amountSent);

    /// EXTERNAL ///

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress)
    {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.supplyLogic.selector,
                _poolTokenAddress,
                msg.sender,
                msg.sender,
                _amount,
                defaultMaxGasForMatching.supply
            )
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external nonReentrant isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress) {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.supplyLogic.selector,
                _poolTokenAddress,
                msg.sender,
                msg.sender,
                _amount,
                _maxGasForMatching
            )
        );
    }

    /// @notice Supplies underlying tokens in a specific market with the supply credited to _onBehalfOf.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _onBehalfOf The address which will be credited for the supply
    /// @param _amount The amount of token (in underlying) to supply.
    function supplyOnBehalf(
        address _poolTokenAddress,
        address _onBehalfOf,
        uint256 _amount
    ) external nonReentrant isMarketCreatedAndNotPausedNorPartiallyPaused(_poolTokenAddress) {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.supplyLogic.selector,
                _poolTokenAddress,
                msg.sender,
                _onBehalfOf,
                _amount,
                defaultMaxGasForMatching.supply
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
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.borrowLogic.selector,
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
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.borrowLogic.selector,
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
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.withdrawLogic.selector,
                _poolTokenAddress,
                msg.sender, // supplier
                msg.sender, // receiver
                _amount,
                defaultMaxGasForMatching.withdraw
            )
        );
    }

    /// @notice Sender withdraws underlying tokens in a specific market to a specified address.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _to The address receiving the underlying tokens.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdrawTo(
        address _poolTokenAddress,
        address _to,
        uint256 _amount
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.withdrawLogic.selector,
                _poolTokenAddress,
                msg.sender, // supplier
                _to, // receiver
                _amount,
                defaultMaxGasForMatching.withdraw
            )
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.repayLogic.selector,
                _poolTokenAddress,
                msg.sender, // user
                msg.sender, // onBehalfOf
                _amount,
                defaultMaxGasForMatching.repay
            )
        );
    }

    /// @notice Repays debt of _onBehalfOf.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _onBehalfOf The address to be credited for the repayment.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repayOnBehalf(
        address _poolTokenAddress,
        address _onBehalfOf,
        uint256 _amount
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.repayLogic.selector,
                _poolTokenAddress,
                msg.sender, // payer
                _onBehalfOf, // onBehalfOf
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
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                positionsManager.liquidateLogic.selector,
                _poolTokenBorrowedAddress,
                _poolTokenCollateralAddress,
                _borrower,
                _amount
            )
        );
    }

    /// @notice Claims rewards for the given assets.
    /// @param _cTokenAddresses The cToken addresses to claim rewards from.
    /// @param _tradeForMorphoToken Whether or not to trade COMP tokens for MORPHO tokens.
    function claimRewards(address[] calldata _cTokenAddresses, bool _tradeForMorphoToken)
        external
        nonReentrant
    {
        uint256 amountOfRewards = rewardsManager.claimRewards(_cTokenAddresses, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();

        ERC20 comp = ERC20(comptroller.getCompAddress());
        // If there is not enough COMP tokens on the contract, claim them. Else, continue.
        if (comp.balanceOf(address(this)) < amountOfRewards)
            comptroller.claimComp(address(this), _cTokenAddresses);

        if (_tradeForMorphoToken) {
            comp.safeApprove(address(incentivesVault), amountOfRewards);
            incentivesVault.tradeCompForMorphoTokens(msg.sender, amountOfRewards);
            emit RewardsClaimedAndTraded(msg.sender, amountOfRewards);
        } else {
            comp.safeTransfer(msg.sender, amountOfRewards);
            emit RewardsClaimed(msg.sender, amountOfRewards);
        }
    }

    /// @notice Allows to receive ETH.
    receive() external payable {}
}
