// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./MorphoUtils.sol";

contract MorphoGettersAndSetters is MorphoUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using MarketLib for Types.Market;
    using SafeTransferLib for ERC20;
    using HeapOrdering for HeapOrdering.HeapArray;

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

    /// GOVERNANCE SETTERS ///

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

    /// @notice Sets `isSupplyPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsSupplyPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        market[_poolToken].isSupplyPaused = _isPaused;
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
        market[_poolToken].isBorrowPaused = _isPaused;
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
        market[_poolToken].isWithdrawPaused = _isPaused;
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
        market[_poolToken].isRepayPaused = _isPaused;
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
        market[_poolToken].isLiquidateCollateralPaused = _isPaused;
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
        market[_poolToken].isLiquidateBorrowPaused = _isPaused;
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
        market[_poolToken].isP2PDisabled = _isP2PDisabled;
        emit IsP2PDisabledSet(_poolToken, _isP2PDisabled);
    }

    /// @notice Sets `isClaimRewardsPaused`.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsClaimRewardsPaused(bool _isPaused) external onlyOwner {
        isClaimRewardsPaused = _isPaused;
        emit IsClaimRewardsPausedSet(_isPaused);
    }

    /// @notice Sets a market as deprecated (allows liquidation of every position on this market).
    /// @param _poolToken The address of the market to update.
    /// @param _isDeprecated The new deprecated status, true to deprecate the market.
    function setIsDeprecated(address _poolToken, bool _isDeprecated)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        market[_poolToken].isDeprecated = _isDeprecated;
        emit IsDeprecatedSet(_poolToken, _isDeprecated);
    }

    /// @notice Sets a market's asset as collateral.
    /// @param _poolToken The address of the market to (un)set as collateral.
    /// @param _assetAsCollateral True to set the asset as collateral (True by default).
    function setAssetAsCollateral(address _poolToken, bool _assetAsCollateral)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        pool.setUserUseReserveAsCollateral(market[_poolToken].underlyingToken, _assetAsCollateral);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market addresses.
    function getMarketsCreated() external view returns (address[] memory) {
        return marketsCreated;
    }

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolToken The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolToken, Types.PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolToken].getHead();
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolToken].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolToken].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolToken].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @dev Beware that this function does not give the account with the highest liquidity.
    /// @param _poolToken The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolToken,
        Types.PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolToken].getNext(_user);
    }

    function supplyBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (uint256 inP2P, uint256 onPool)
    {
        return _supplyBalanceInOf(_poolToken, _user);
    }

    function borrowBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (uint256 inP2P, uint256 onPool)
    {
        return _borrowBalanceInOf(_poolToken, _user);
    }
}
