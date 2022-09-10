// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "./MorphoUtils.sol";

/// @title MorphoGovernance.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Governance functions for Morpho.
abstract contract MorphoGovernance is MorphoUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using MarketLib for Types.Market;
    using WadRayMath for uint256;

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
    event P2PStatusSet(address indexed _poolToken, bool _isP2PDisabled);

    /// @notice Emitted when a supply is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event SupplyPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a borrow is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event BorrowPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a withdraw is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event WithdrawPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a repay is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event RepayPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a liquidate as collateral is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event LiquidateCollateralPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a liquidate as borrow is paused or unpaused.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event LiquidateBorrowPauseStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when a market is set as deprecated or not.
    /// @param _poolToken The address of the concerned market.
    /// @param _newStatus The new deprecated status.
    event DeprecatedStatusSet(address indexed _poolToken, bool _newStatus);

    /// @notice Emitted when claiming rewards is paused or unpaused.
    /// @param _newStatus The new claiming rewards status.
    event ClaimRewardsPauseStatusSet(bool _newStatus);

    /// @notice Emitted when a new market is created.
    /// @param _poolToken The address of the market that has been created.
    /// @param _reserveFactor The reserve factor set for this market.
    /// @param _poolToken The P2P index cursor set for this market.
    event MarketCreated(address indexed _poolToken, uint16 _reserveFactor, uint16 _p2pIndexCursor);

    /// ERRORS ///

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

    /// UPGRADE ///

    /// @notice Initializes the Morpho contract.
    /// @param _entryPositionsManager The `entryPositionsManager`.
    /// @param _exitPositionsManager The `exitPositionsManager`.
    /// @param _interestRatesManager The `interestRatesManager`.
    /// @param _lendingPoolAddressesProvider The `addressesProvider`.
    /// @param _defaultMaxGasForMatching The `defaultMaxGasForMatching`.
    /// @param _maxSortedUsers The `_maxSortedUsers`.
    function initialize(
        IEntryPositionsManager _entryPositionsManager,
        IExitPositionsManager _exitPositionsManager,
        IInterestRatesManager _interestRatesManager,
        IPoolAddressesProvider _lendingPoolAddressesProvider,
        Types.MaxGasForMatching memory _defaultMaxGasForMatching,
        uint256 _maxSortedUsers
    ) external initializer {
        if (_maxSortedUsers == 0) revert MaxSortedUsersCannotBeZero();

        __ReentrancyGuard_init();
        __Ownable_init();

        interestRatesManager = _interestRatesManager;
        entryPositionsManager = _entryPositionsManager;
        exitPositionsManager = _exitPositionsManager;
        addressesProvider = _lendingPoolAddressesProvider;
        pool = IPool(addressesProvider.getPool());

        defaultMaxGasForMatching = _defaultMaxGasForMatching;
        maxSortedUsers = _maxSortedUsers;
    }

    /// GOVERNANCE ///

    /// @notice Sets `maxSortedUsers`.
    /// @param _newMaxSortedUsers The new `maxSortedUsers` value.
    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external onlyOwner {
        if (_newMaxSortedUsers == 0) revert MaxSortedUsersCannotBeZero();
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

    /// @notice Sets the `entryPositionsManager`.
    /// @param _entryPositionsManager The new `entryPositionsManager`.
    function setEntryPositionsManager(IEntryPositionsManager _entryPositionsManager)
        external
        onlyOwner
    {
        if (address(_entryPositionsManager) == address(0)) revert ZeroAddress();
        entryPositionsManager = _entryPositionsManager;
        emit EntryPositionsManagerSet(address(_entryPositionsManager));
    }

    /// @notice Sets the `exitPositionsManager`.
    /// @param _exitPositionsManager The new `exitPositionsManager`.
    function setExitPositionsManager(IExitPositionsManager _exitPositionsManager)
        external
        onlyOwner
    {
        if (address(_exitPositionsManager) == address(0)) revert ZeroAddress();
        exitPositionsManager = _exitPositionsManager;
        emit ExitPositionsManagerSet(address(_exitPositionsManager));
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

    /// @notice Sets the `rewardsController`.
    /// @param _rewardsController The address of the new `rewardsController`.
    function setRewardsController(address _rewardsController) external onlyOwner {
        rewardsController = IRewardsController(_rewardsController);
        emit RewardsControllerSet(_rewardsController);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _incentivesVault The new `incentivesVault`.
    function setIncentivesVault(IIncentivesVault _incentivesVault) external onlyOwner {
        incentivesVault = _incentivesVault;
        emit IncentivesVaultSet(address(_incentivesVault));
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
        _updateIndexes(_poolToken);

        market[_poolToken].reserveFactor = _newReserveFactor;
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
        _updateIndexes(_poolToken);

        market[_poolToken].p2pIndexCursor = _p2pIndexCursor;
        emit P2PIndexCursorSet(_poolToken, _p2pIndexCursor);
    }

    /// @notice Sets the supply pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setSupplyPauseStatus(address _poolToken, bool _newStatus) external onlyOwner {
        market[_poolToken].isSupplyPaused = _newStatus;
        emit SupplyPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the borrow pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setBorrowPauseStatus(address _poolToken, bool _newStatus) external onlyOwner {
        market[_poolToken].isBorrowPaused = _newStatus;
        emit BorrowPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the withdraw pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setWithdrawPauseStatus(address _poolToken, bool _newStatus) external onlyOwner {
        market[_poolToken].isWithdrawPaused = _newStatus;
        emit WithdrawPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the supply pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setRepayPauseStatus(address _poolToken, bool _newStatus) external onlyOwner {
        market[_poolToken].isRepayPaused = _newStatus;
        emit RepayPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the liquidate collateral pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setLiquidateCollateralPauseStatus(address _poolToken, bool _newStatus)
        external
        onlyOwner
    {
        market[_poolToken].isLiquidateCollateralPaused = _newStatus;
        emit LiquidateCollateralPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the supply pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setLiquidateBorrowPauseStatus(address _poolToken, bool _newStatus) external onlyOwner {
        market[_poolToken].isLiquidateBorrowPaused = _newStatus;
        emit LiquidateBorrowPauseStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the pause status for all markets.
    /// @param _newStatus The new status to set.
    function setPauseStatusForAllMarkets(bool _newStatus) external onlyOwner {
        uint256 numberOfMarketsCreated = marketsCreated.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[i];

            _setPauseStatus(poolToken, _newStatus);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the peer-to-peer disable status.
    /// @param _poolToken The address of the market of which to enable/disable peer-to-peer matching.
    /// @param _newStatus The new status to set.
    function setP2PDisabledStatus(address _poolToken, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        market[_poolToken].isP2PDisabled = _newStatus;
        emit P2PStatusSet(_poolToken, _newStatus);
    }

    /// @notice Sets the pause status on claiming rewards.
    /// @param _newStatus The new status to set.
    function setClaimRewardsPauseStatus(bool _newStatus) external onlyOwner {
        isClaimRewardsPaused = _newStatus;
        emit ClaimRewardsPauseStatusSet(_newStatus);
    }

    /// @notice Sets a market's asset as collateral.
    /// @param _poolToken The address of the market to (un)set as collateral.
    /// @param _newStatus The new status to set.
    function setAssetAsCollateral(address _poolToken, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        pool.setUserUseReserveAsCollateral(market[_poolToken].underlyingToken, _newStatus);
    }

    /// @notice Sets a market as deprecated (allows liquidation of every positions on this market).
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function setDeprecatedStatus(address _poolToken, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        market[_poolToken].isDeprecated = _newStatus;
        emit DeprecatedStatusSet(_poolToken, _newStatus);
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

            Types.Market memory market = market[poolToken];
            if (!market.isCreatedMemory()) continue;

            ERC20 underlyingToken = ERC20(market.underlyingToken);
            uint256 underlyingBalance = underlyingToken.balanceOf(address(this));

            if (underlyingBalance == 0) continue;

            uint256 toClaim = Math.min(_amounts[i], underlyingBalance);

            underlyingToken.safeTransfer(treasuryVault, toClaim);
            emit ReserveFeeClaimed(poolToken, toClaim);
        }
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _underlyingToken The underlying token address.
    /// @param _reserveFactor The reserve factor to set on this market.
    /// @param _p2pIndexCursor The peer-to-peer index cursor to set on this market.
    function createMarket(
        address _underlyingToken,
        uint16 _reserveFactor,
        uint16 _p2pIndexCursor
    ) external onlyOwner {
        if (marketsCreated.length >= MAX_NB_OF_MARKETS) revert MaxNumberOfMarkets();
        if (_underlyingToken == address(0)) revert ZeroAddress();
        if (_p2pIndexCursor > MAX_BASIS_POINTS || _reserveFactor > MAX_BASIS_POINTS)
            revert ExceedsMaxBasisPoints();

        if (!pool.getConfiguration(_underlyingToken).getActive()) revert MarketIsNotListedOnAave();

        address poolToken = pool.getReserveData(_underlyingToken).aTokenAddress;

        if (market[poolToken].isCreated()) revert MarketAlreadyCreated();

        p2pSupplyIndex[poolToken] = WadRayMath.RAY;
        p2pBorrowIndex[poolToken] = WadRayMath.RAY;

        Types.PoolIndexes storage poolIndexes = poolIndexes[poolToken];

        poolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
        poolIndexes.poolSupplyIndex = uint112(pool.getReserveNormalizedIncome(_underlyingToken));
        poolIndexes.poolBorrowIndex = uint112(
            pool.getReserveNormalizedVariableDebt(_underlyingToken)
        );

        market[poolToken] = Types.Market({
            underlyingToken: _underlyingToken,
            reserveFactor: _reserveFactor,
            p2pIndexCursor: _p2pIndexCursor,
            isSupplyPaused: false,
            isBorrowPaused: false,
            isP2PDisabled: false,
            isWithdrawPaused: false,
            isRepayPaused: false,
            isLiquidateCollateralPaused: false,
            isLiquidateBorrowPaused: false,
            isDeprecated: false
        });

        borrowMask[poolToken] = ONE << (marketsCreated.length << 1);
        marketsCreated.push(poolToken);

        ERC20(_underlyingToken).safeApprove(address(pool), type(uint256).max);

        emit MarketCreated(poolToken, _reserveFactor, _p2pIndexCursor);
    }

    /// INTERNAL ///

    /// @notice Sets the different pause status for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _newStatus The new status to set.
    function _setPauseStatus(address _poolToken, bool _newStatus) internal {
        Types.Market storage market = market[_poolToken];

        market.isSupplyPaused = _newStatus;
        market.isBorrowPaused = _newStatus;
        market.isWithdrawPaused = _newStatus;
        market.isRepayPaused = _newStatus;
        market.isLiquidateCollateralPaused = _newStatus;
        market.isLiquidateBorrowPaused = _newStatus;

        emit SupplyPauseStatusSet(_poolToken, _newStatus);
        emit BorrowPauseStatusSet(_poolToken, _newStatus);
        emit WithdrawPauseStatusSet(_poolToken, _newStatus);
        emit RepayPauseStatusSet(_poolToken, _newStatus);
        emit LiquidateCollateralPauseStatusSet(_poolToken, _newStatus);
        emit LiquidateBorrowPauseStatusSet(_poolToken, _newStatus);
    }
}
