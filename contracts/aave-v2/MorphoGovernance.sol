// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "./libraries/Math.sol";

import "./MorphoUtils.sol";

/// @title MorphoGovernance.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Governance functions for Morpho.
abstract contract MorphoGovernance is MorphoUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
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

    /// @notice Emitted when the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address indexed _aaveIncentivesController);

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolTokenAddress, uint16 _newValue);

    /// @notice Emitted when the `p2pIndexCursor` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newValue The new value of the `p2pIndexCursor`.
    event P2PIndexCursorSet(address indexed _poolTokenAddress, uint16 _newValue);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address indexed _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when the value of `p2pDisabled` is set.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _p2pDisabled The new value of `_p2pDisabled` adopted.
    event P2PStatusSet(address indexed _poolTokenAddress, bool _p2pDisabled);

    /// @notice Emitted when a market is paused or unpaused.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newStatus The new pause status of the market.
    event PauseStatusSet(address indexed _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when a market is partially paused or unpaused.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _newStatus The new partial pause status of the market.
    event PartialPauseStatusSet(address indexed _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when claiming rewards is paused or unpaused.
    /// @param _newStatus The new claiming rewards status.
    event ClaimRewardsPauseStatusSet(bool _newStatus);

    /// @notice Emitted when a new market is created.
    /// @param _poolTokenAddress The address of the market that has been created.
    /// @param _reserveFactor The reserve factor set for this market.
    /// @param _poolTokenAddress The P2P index cursor set for this market.
    event MarketCreated(
        address indexed _poolTokenAddress,
        uint16 _reserveFactor,
        uint16 _p2pIndexCursor
    );

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
        ILendingPoolAddressesProvider _lendingPoolAddressesProvider,
        Types.MaxGasForMatching memory _defaultMaxGasForMatching,
        uint256 _maxSortedUsers
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        interestRatesManager = _interestRatesManager;
        entryPositionsManager = _entryPositionsManager;
        exitPositionsManager = _exitPositionsManager;
        addressesProvider = _lendingPoolAddressesProvider;
        pool = ILendingPool(addressesProvider.getLendingPool());

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

    /// @notice Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController) external onlyOwner {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _incentivesVault The new `incentivesVault`.
    function setIncentivesVault(IIncentivesVault _incentivesVault) external onlyOwner {
        incentivesVault = _incentivesVault;
        emit IncentivesVaultSet(address(_incentivesVault));
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _poolTokenAddress The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _poolTokenAddress, uint16 _newReserveFactor)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        if (_newReserveFactor > MAX_BASIS_POINTS) revert ExceedsMaxBasisPoints();
        _updateIndexes(_poolTokenAddress);

        marketInfos[_poolTokenAddress].reserveFactor = _newReserveFactor;
        emit ReserveFactorSet(_poolTokenAddress, _newReserveFactor);
    }

    /// @notice Sets a new peer-to-peer cursor.
    /// @param _poolTokenAddress The address of the market to update.
    /// @param _p2pIndexCursor The new peer-to-peer cursor.
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        if (_p2pIndexCursor > MAX_BASIS_POINTS) revert ExceedsMaxBasisPoints();
        _updateIndexes(_poolTokenAddress);

        marketInfos[_poolTokenAddress].p2pIndexCursor = _p2pIndexCursor;
        emit P2PIndexCursorSet(_poolTokenAddress, _p2pIndexCursor);
    }

    /// @notice Sets the pause status for all markets.
    /// @param _newStatus The new status to set.
    function setPauseStatusForAllMarkets(bool _newStatus) external onlyOwner {
        uint256 numberOfMarketsCreated = marketsCreated.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[i];

            marketInfos[poolToken].isPaused = _newStatus;
            emit PauseStatusSet(poolToken, _newStatus);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    /// @param _newStatus The new status to set.
    function setPauseStatus(address _poolTokenAddress, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        marketInfos[_poolTokenAddress].isPaused = _newStatus;
        emit PauseStatusSet(_poolTokenAddress, _newStatus);
    }

    /// @notice Sets the partial pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to partially pause/unpause.
    /// @param _newStatus The new status to set.
    function setPartialPauseStatus(address _poolTokenAddress, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        marketInfos[_poolTokenAddress].isPartiallyPaused = _newStatus;
        emit PartialPauseStatusSet(_poolTokenAddress, _newStatus);
    }

    /// @notice Sets the peer-to-peer disable status.
    /// @param _poolTokenAddress The address of the market of which to enable/disable peer-to-peer matching.
    /// @param _newStatus The new status to set.
    function setP2PDisabled(address _poolTokenAddress, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        p2pDisabled[_poolTokenAddress] = _newStatus;
        emit P2PStatusSet(_poolTokenAddress, _newStatus);
    }

    /// @notice Sets the pause status on claiming rewards.
    /// @param _newStatus The new status to set.
    function setClaimRewardsPauseStatus(bool _newStatus) external onlyOwner {
        isClaimRewardsPaused = _newStatus;
        emit ClaimRewardsPauseStatusSet(_newStatus);
    }

    /// @notice Sets a market's asset as collateral.
    /// @param _poolTokenAddress The address of the market to (un)set as collateral.
    /// @param _newStatus The new status to set.
    function setAssetAsCollateral(address _poolTokenAddress, bool _newStatus)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        pool.setUserUseReserveAsCollateral(
            marketInfos[_poolTokenAddress].underlyingToken,
            _newStatus
        );
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddresses The addresses of the pool token addresses on which to claim the reserve fee.
    function claimToTreasury(address[] calldata _poolTokenAddresses) external onlyOwner {
        if (treasuryVault == address(0)) revert ZeroAddress();

        uint256 numberOfMarkets = _poolTokenAddresses.length;

        for (uint256 i; i < numberOfMarkets; ++i) {
            address poolToken = _poolTokenAddresses[i];

            Types.MarketInfos memory status = marketInfos[poolToken];
            if (!status.isCreated || status.isPaused || status.isPartiallyPaused) continue;

            ERC20 underlyingToken = ERC20(marketInfos[poolToken].underlyingToken);
            uint256 underlyingBalance = underlyingToken.balanceOf(address(this));

            if (underlyingBalance == 0) continue;

            underlyingToken.safeTransfer(
                treasuryVault,
                underlyingBalance.percentMul(MAX_CLAIMABLE_RESERVE)
            );
            emit ReserveFeeClaimed(poolToken, underlyingBalance);
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

        address poolTokenAddress = pool.getReserveData(_underlyingToken).aTokenAddress;

        if (marketInfos[poolTokenAddress].isCreated) revert MarketAlreadyCreated();

        p2pSupplyIndex[poolTokenAddress] = WadRayMath.RAY;
        p2pBorrowIndex[poolTokenAddress] = WadRayMath.RAY;

        Types.PoolIndexes storage poolIndexes = poolIndexes[poolTokenAddress];

        poolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
        poolIndexes.poolSupplyIndex = uint112(pool.getReserveNormalizedIncome(_underlyingToken));
        poolIndexes.poolBorrowIndex = uint112(
            pool.getReserveNormalizedVariableDebt(_underlyingToken)
        );

        marketInfos[poolTokenAddress] = Types.MarketInfos({
            underlyingToken: _underlyingToken,
            reserveFactor: _reserveFactor,
            p2pIndexCursor: _p2pIndexCursor,
            isCreated: true,
            isPaused: false,
            isPartiallyPaused: false
        });

        borrowMask[poolTokenAddress] = ONE << (marketsCreated.length << 1);
        marketsCreated.push(poolTokenAddress);

        ERC20(_underlyingToken).safeApprove(address(pool), type(uint256).max);

        emit MarketCreated(poolTokenAddress, _reserveFactor, _p2pIndexCursor);
    }
}
