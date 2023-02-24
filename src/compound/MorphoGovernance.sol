// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./MorphoUtils.sol";

/// @title MorphoGovernance.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Governance functions for Morpho.
abstract contract MorphoGovernance is MorphoUtils {
    using SafeTransferLib for ERC20;
    using DelegateCall for address;

    /// EVENTS ///

    /// @notice Emitted when a new `defaultMaxGasForMatching` is set.
    /// @param _defaultMaxGasForMatching The new `defaultMaxGasForMatching`.
    event DefaultMaxGasForMatchingSet(Types.MaxGasForMatching _defaultMaxGasForMatching);

    /// @notice Emitted when a new value for `maxSortedUsers` is set.
    /// @param _newValue The new value of `maxSortedUsers`.
    event MaxSortedUsersSet(uint256 _newValue);

    /// @notice Emitted when the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address indexed _newTreasuryVaultAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The new address of the `positionsManager`.
    event PositionsManagerSet(address indexed _positionsManager);

    /// @notice Emitted when the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address indexed _newRewardsManagerAddress);

    /// @notice Emitted when the `interestRatesManager` is set.
    /// @param _interestRatesManager The new address of the `interestRatesManager`.
    event InterestRatesSet(address indexed _interestRatesManager);

    /// @dev Emitted when a new `dustThreshold` is set.
    /// @param _dustThreshold The new `dustThreshold`.
    event DustThresholdSet(uint256 _dustThreshold);

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
    event P2PStatusSet(address indexed _poolToken, bool _isP2PDisabled);

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
    event ClaimRewardsPauseStatusSet(bool _isPaused);

    /// @notice Emitted when a new market is created.
    /// @param _poolToken The address of the market that has been created.
    /// @param _reserveFactor The reserve factor set for this market.
    /// @param _p2pIndexCursor The P2P index cursor set for this market.
    event MarketCreated(address indexed _poolToken, uint16 _reserveFactor, uint16 _p2pIndexCursor);

    /// ERRORS ///

    /// @notice Thrown when the creation of a market failed on Compound and kicks back Compound error code.
    error MarketCreationFailedOnCompound(uint256 errorCode);

    /// @notice Thrown when the input is above the max basis points value (100%).
    error ExceedsMaxBasisPoints();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();

    /// @notice Thrown when market borrow is not paused.
    error BorrowNotPaused();

    /// @notice Thrown when market is deprecated.
    error MarketIsDeprecated();

    /// UPGRADE ///

    /// @notice Initializes the Morpho contract.
    /// @param _positionsManager The `positionsManager`.
    /// @param _interestRatesManager The `interestRatesManager`.
    /// @param _comptroller The `comptroller`.
    /// @param _defaultMaxGasForMatching The `defaultMaxGasForMatching`.
    /// @param _dustThreshold The `dustThreshold`.
    /// @param _maxSortedUsers The `_maxSortedUsers`.
    /// @param _cEth The cETH address.
    /// @param _wEth The wETH address.
    function initialize(
        IPositionsManager _positionsManager,
        IInterestRatesManager _interestRatesManager,
        IComptroller _comptroller,
        Types.MaxGasForMatching memory _defaultMaxGasForMatching,
        uint256 _dustThreshold,
        uint256 _maxSortedUsers,
        address _cEth,
        address _wEth
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        interestRatesManager = _interestRatesManager;
        positionsManager = _positionsManager;
        comptroller = _comptroller;

        defaultMaxGasForMatching = _defaultMaxGasForMatching;
        dustThreshold = _dustThreshold;
        maxSortedUsers = _maxSortedUsers;

        cEth = _cEth;
        wEth = _wEth;
    }

    /// GOVERNANCE ///

    /// @notice Sets `maxSortedUsers`.
    /// @param _newMaxSortedUsers The new `maxSortedUsers` value.
    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external onlyOwner {
        maxSortedUsers = _newMaxSortedUsers;
        emit MaxSortedUsersSet(_newMaxSortedUsers);
    }

    /// @notice Sets `defaultMaxGasForMatching`.
    /// @param _defaultMaxGasForMatching The new `defaultMaxGasForMatching`.
    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _defaultMaxGasForMatching)
        external
        onlyOwner
    {
        defaultMaxGasForMatching = _defaultMaxGasForMatching;
        emit DefaultMaxGasForMatchingSet(_defaultMaxGasForMatching);
    }

    /// @notice Sets the `positionsManager`.
    /// @param _positionsManager The new `positionsManager`.
    function setPositionsManager(IPositionsManager _positionsManager) external onlyOwner {
        if (address(_positionsManager) == address(0)) revert ZeroAddress();
        positionsManager = _positionsManager;
        emit PositionsManagerSet(address(_positionsManager));
    }

    /// @notice Sets the `interestRatesManager`.
    /// @param _interestRatesManager The new `interestRatesManager` contract.
    function setInterestRatesManager(IInterestRatesManager _interestRatesManager)
        external
        onlyOwner
    {
        if (address(_interestRatesManager) == address(0)) revert ZeroAddress();
        interestRatesManager = _interestRatesManager;
        emit InterestRatesSet(address(_interestRatesManager));
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManager The new `rewardsManager`.
    function setRewardsManager(IRewardsManager _rewardsManager) external onlyOwner {
        rewardsManager = _rewardsManager;
        emit RewardsManagerSet(address(_rewardsManager));
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _treasuryVault The address of the new `treasuryVault`.
    function setTreasuryVault(address _treasuryVault) external onlyOwner {
        treasuryVault = _treasuryVault;
        emit TreasuryVaultSet(_treasuryVault);
    }

    /// @dev Sets `dustThreshold`.
    /// @param _dustThreshold The new `dustThreshold`.
    function setDustThreshold(uint256 _dustThreshold) external onlyOwner {
        dustThreshold = _dustThreshold;
        emit DustThresholdSet(_dustThreshold);
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _poolToken The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _poolToken, uint16 _newReserveFactor)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (_newReserveFactor > MAX_BASIS_POINTS) revert ExceedsMaxBasisPoints();
        _updateP2PIndexes(_poolToken);

        marketParameters[_poolToken].reserveFactor = _newReserveFactor;
        emit ReserveFactorSet(_poolToken, _newReserveFactor);
    }

    /// @notice Sets a new peer-to-peer cursor.
    /// @param _poolToken The address of the market to update.
    /// @param _p2pIndexCursor The new peer-to-peer cursor.
    function setP2PIndexCursor(address _poolToken, uint16 _p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (_p2pIndexCursor > MAX_BASIS_POINTS) revert ExceedsMaxBasisPoints();
        _updateP2PIndexes(_poolToken);

        marketParameters[_poolToken].p2pIndexCursor = _p2pIndexCursor;
        emit P2PIndexCursorSet(_poolToken, _p2pIndexCursor);
    }

    /// @notice Sets `isSupplyPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsSupplyPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        marketPauseStatus[_poolToken].isSupplyPaused = _isPaused;
        emit IsSupplyPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isBorrowPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsBorrowPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (!_isPaused && marketPauseStatus[_poolToken].isDeprecated) revert MarketIsDeprecated();
        marketPauseStatus[_poolToken].isBorrowPaused = _isPaused;
        emit IsBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isWithdrawPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsWithdrawPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        marketPauseStatus[_poolToken].isWithdrawPaused = _isPaused;
        emit IsWithdrawPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isRepayPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsRepayPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        marketPauseStatus[_poolToken].isRepayPaused = _isPaused;
        emit IsRepayPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isLiquidateCollateralPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsLiquidateCollateralPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        marketPauseStatus[_poolToken].isLiquidateCollateralPaused = _isPaused;
        emit IsLiquidateCollateralPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isLiquidateBorrowPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsLiquidateBorrowPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        marketPauseStatus[_poolToken].isLiquidateBorrowPaused = _isPaused;
        emit IsLiquidateBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets the pause status for all markets.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsPausedForAllMarkets(bool _isPaused) external onlyOwner {
        uint256 numberOfMarketsCreated = marketsCreated.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[i];

            _setPauseStatus(poolToken, _isPaused);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets `isP2PDisabled` for a given market.
    /// @param _poolToken The address of the market of which to enable/disable peer-to-peer matching.
    /// @param _isP2PDisabled True to disable the peer-to-peer market.
    function setIsP2PDisabled(address _poolToken, bool _isP2PDisabled)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        p2pDisabled[_poolToken] = _isP2PDisabled;
        emit P2PStatusSet(_poolToken, _isP2PDisabled);
    }

    /// @notice Sets `isClaimRewardsPaused`.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsClaimRewardsPaused(bool _isPaused) external onlyOwner {
        isClaimRewardsPaused = _isPaused;
        emit ClaimRewardsPauseStatusSet(_isPaused);
    }

    /// @notice Sets a market as deprecated (allows liquidation of every position on this market).
    /// @param _poolToken The address of the market to update.
    /// @param _isDeprecated The new deprecated status, true to deprecate the market.
    function setIsDeprecated(address _poolToken, bool _isDeprecated)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (!marketPauseStatus[_poolToken].isBorrowPaused) revert BorrowNotPaused();
        marketPauseStatus[_poolToken].isDeprecated = _isDeprecated;
        emit IsDeprecatedSet(_poolToken, _isDeprecated);
    }

    /// @notice Increases peer-to-peer deltas, to put some liquidity back on the pool.
    /// @dev The current Morpho supply on the pool might not be enough to borrow `_amount` before resuppling it.
    /// In this case, consider calling multiple times this function.
    /// @param _poolToken The address of the market on which to increase deltas.
    /// @param _amount The maximum amount to add to the deltas (in underlying).
    function increaseP2PDeltas(address _poolToken, uint256 _amount) external onlyOwner {
        address(positionsManager).functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.increaseP2PDeltasLogic.selector,
                _poolToken,
                _amount
            )
        );
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokens The addresses of the pool token addresses on which to claim the reserve fee.
    /// @param _amounts The list of amounts of underlying tokens to claim on each market.
    function claimToTreasury(address[] calldata _poolTokens, uint256[] calldata _amounts)
        external
        onlyOwner
    {
        if (treasuryVault == address(0)) revert ZeroAddress();

        uint256 numberOfMarkets = _poolTokens.length;

        for (uint256 i; i < numberOfMarkets; ++i) {
            address poolToken = _poolTokens[i];

            Types.MarketStatus memory status = marketStatus[poolToken];
            if (!status.isCreated) continue;

            ERC20 underlyingToken = _getUnderlying(poolToken);
            uint256 underlyingBalance = underlyingToken.balanceOf(address(this));

            if (underlyingBalance == 0) continue;

            uint256 toClaim = Math.min(_amounts[i], underlyingBalance);

            underlyingToken.safeTransfer(treasuryVault, toClaim);
            emit ReserveFeeClaimed(poolToken, toClaim);
        }
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolToken The pool token address of the given market.
    /// @param _marketParams The market's parameters to set.
    function createMarket(address _poolToken, Types.MarketParameters calldata _marketParams)
        external
        onlyOwner
    {
        if (
            _marketParams.p2pIndexCursor > MAX_BASIS_POINTS ||
            _marketParams.reserveFactor > MAX_BASIS_POINTS
        ) revert ExceedsMaxBasisPoints();

        if (marketStatus[_poolToken].isCreated) revert MarketAlreadyCreated();
        marketStatus[_poolToken].isCreated = true;

        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolToken;
        uint256[] memory results = comptroller.enterMarkets(marketToEnter);
        if (results[0] != 0) revert MarketCreationFailedOnCompound(results[0]);

        // Same initial index as Compound.
        uint256 initialIndex;
        if (_poolToken == cEth) initialIndex = 2e26;
        else initialIndex = 2 * 10**(16 + ERC20(ICToken(_poolToken).underlying()).decimals() - 8);
        p2pSupplyIndex[_poolToken] = initialIndex;
        p2pBorrowIndex[_poolToken] = initialIndex;

        Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolToken];

        poolIndexes.lastUpdateBlockNumber = uint32(block.number);
        poolIndexes.lastSupplyPoolIndex = uint112(ICToken(_poolToken).exchangeRateCurrent());
        poolIndexes.lastBorrowPoolIndex = uint112(ICToken(_poolToken).borrowIndex());

        marketParameters[_poolToken] = _marketParams;

        marketsCreated.push(_poolToken);
        emit MarketCreated(_poolToken, _marketParams.reserveFactor, _marketParams.p2pIndexCursor);
    }

    /// INTERNAL ///

    /// @notice Sets all pause statuses for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function _setPauseStatus(address _poolToken, bool _isPaused) internal {
        Types.MarketPauseStatus storage pause = marketPauseStatus[_poolToken];

        pause.isSupplyPaused = _isPaused;
        emit IsSupplyPausedSet(_poolToken, _isPaused);

        // Note that pause.isDeprecated implies pause.isBorrowPaused.
        if (!pause.isDeprecated) {
            pause.isBorrowPaused = _isPaused;
            emit IsBorrowPausedSet(_poolToken, _isPaused);
        }

        pause.isWithdrawPaused = _isPaused;
        emit IsWithdrawPausedSet(_poolToken, _isPaused);

        pause.isRepayPaused = _isPaused;
        emit IsRepayPausedSet(_poolToken, _isPaused);

        pause.isLiquidateCollateralPaused = _isPaused;
        emit IsLiquidateCollateralPausedSet(_poolToken, _isPaused);

        pause.isLiquidateBorrowPaused = _isPaused;
        emit IsLiquidateBorrowPausedSet(_poolToken, _isPaused);
    }
}
