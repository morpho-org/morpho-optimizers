// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./MorphoUtils.sol";

/// @title MorphoGovernance.
/// @notice Governance functions for Morpho.
abstract contract MorphoGovernance is MorphoUtils {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;
    using DelegateCall for address;

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

    /// @notice Emitted when the `interestRatesManager` is set.
    /// @param _interestRatesManager The new address of the `interestRatesManager`.
    event InterestRatesSet(address indexed _interestRatesManager);

    /// @dev Emitted when a new `dustThreshold` is set.
    /// @param _dustThreshold The new `dustThreshold`.
    event DustThresholdSet(uint256 _dustThreshold);

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

    /// @notice Emitted when a COMP reward status is changed.
    /// @param _isCompRewardsActive The new COMP reward status.
    event CompRewardsStatusChanged(bool _isCompRewardsActive);

    /// @notice Emitted when the value of `p2pDisabled` is changed.
    /// @param _poolTokenAddress The address of the concerned market.
    /// @param _p2pDisabled The new value of `_p2pDisabled` adopted.
    event P2PStatusChanged(address indexed _poolTokenAddress, bool _p2pDisabled);

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

    /// @notice Thrown when the input is above the max basis points value (100%).
    error ExceedsMaxBasisPoints();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();

    /// UPGRADE ///

    /// @notice Initializes the Morpho contract.
    /// @param _positionsManager The `positionsManager`.
    /// @param _interestRatesManager The `interestRatesManager`.
    /// @param _comptroller The `comptroller`.
    /// @param _maxGasForMatching The `maxGasForMatching`.
    /// @param _dustThreshold The `dustThreshold`.
    /// @param _maxSortedUsers The `_maxSortedUsers`.
    /// @param _cEth The cETH address.
    /// @param _wEth The wETH address.
    function initialize(
        IPositionsManager _positionsManager,
        IInterestRatesManager _interestRatesManager,
        IComptroller _comptroller,
        Types.MaxGasForMatching memory _maxGasForMatching,
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

        maxGasForMatching = _maxGasForMatching;
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

    /// @notice Sets `maxGasForMatching`.
    /// @param _maxGasForMatching The new `maxGasForMatching`.
    function setMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching)
        external
        onlyOwner
    {
        maxGasForMatching = _maxGasForMatching;
        emit MaxGasForMatchingSet(_maxGasForMatching);
    }

    /// @notice Sets the `positionsManager`.
    /// @param _positionsManager The new `positionsManager`.
    function setPositionsManager(IPositionsManager _positionsManager) external onlyOwner {
        positionsManager = _positionsManager;
        emit PositionsManagerSet(address(_positionsManager));
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManager The new `rewardsManager`.
    function setRewardsManager(IRewardsManager _rewardsManager) external onlyOwner {
        rewardsManager = _rewardsManager;
        emit RewardsManagerSet(address(_rewardsManager));
    }

    /// @notice Sets the `interestRatesManager`.
    /// @param _interestRatesManager The new `interestRatesManager` contract.
    function setInterestRates(IInterestRatesManager _interestRatesManager) external onlyOwner {
        interestRatesManager = _interestRatesManager;
        emit InterestRatesSet(address(_interestRatesManager));
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _treasuryVault The address of the new `treasuryVault`.
    function setTreasuryVault(address _treasuryVault) external onlyOwner {
        treasuryVault = _treasuryVault;
        emit TreasuryVaultSet(_treasuryVault);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _incentivesVault The new `incentivesVault`.
    function setIncentivesVault(IIncentivesVault _incentivesVault) external onlyOwner {
        incentivesVault = _incentivesVault;
        emit IncentivesVaultSet(address(_incentivesVault));
    }

    /// @dev Sets `dustThreshold`.
    /// @param _dustThreshold The new `dustThreshold`.
    function setDustThreshold(uint256 _dustThreshold) external onlyOwner {
        dustThreshold = _dustThreshold;
        emit DustThresholdSet(_dustThreshold);
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
        updateP2PIndexes(_poolTokenAddress);

        marketParameters[_poolTokenAddress].reserveFactor = _newReserveFactor;
        emit ReserveFactorSet(_poolTokenAddress, marketParameters[_poolTokenAddress].reserveFactor);
    }

    /// @notice Sets a new peer-to-peer cursor.
    /// @param _p2pIndexCursor The new peer-to-peer cursor.
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        if (_p2pIndexCursor > MAX_BASIS_POINTS) revert ExceedsMaxBasisPoints();
        updateP2PIndexes(_poolTokenAddress);

        marketParameters[_poolTokenAddress].p2pIndexCursor = _p2pIndexCursor;
        emit P2PIndexCursorSet(_poolTokenAddress, _p2pIndexCursor);
    }

    /// @notice Toggles the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function togglePauseStatus(address _poolTokenAddress)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        Types.MarketStatus storage marketStatus_ = marketStatus[_poolTokenAddress];
        bool newPauseStatus = !marketStatus_.isPaused;
        marketStatus_.isPaused = newPauseStatus;
        emit PauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the partial pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to partially pause/unpause.
    function togglePartialPauseStatus(address _poolTokenAddress)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        Types.MarketStatus storage marketStatus_ = marketStatus[_poolTokenAddress];
        bool newPauseStatus = !marketStatus_.isPartiallyPaused;
        marketStatus_.isPartiallyPaused = newPauseStatus;
        emit PartialPauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the peer-to-peer disable status.
    /// @param _poolTokenAddress The address of the market to able/disable P2P.
    function toggleP2P(address _poolTokenAddress)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        bool newP2PStatus = !p2pDisabled[_poolTokenAddress];
        p2pDisabled[_poolTokenAddress] = newP2PStatus;
        emit P2PStatusChanged(_poolTokenAddress, newP2PStatus);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !isCompRewardsActive;
        isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsStatusChanged(newCompRewardsActive);
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @dev No more than 90% of the accumulated fees are claimable at once.
    /// @param _poolTokenAddress The address of the market on which to claim the reserve fee.
    /// @param _amount The amount of underlying to claim.
    function claimToTreasury(address _poolTokenAddress, uint256 _amount)
        external
        onlyOwner
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        if (treasuryVault == address(0)) revert ZeroAddress();

        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        uint256 underlyingBalance = underlyingToken.balanceOf(address(this));

        if (underlyingBalance == 0) revert AmountIsZero();

        uint256 amountToClaim = Math.min(
            _amount,
            (underlyingBalance * MAX_CLAIMABLE_RESERVE) / MAX_BASIS_POINTS
        );

        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) external onlyOwner {
        if (marketStatus[_poolTokenAddress].isCreated) revert MarketAlreadyCreated();
        marketStatus[_poolTokenAddress].isCreated = true;

        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        uint256[] memory results = comptroller.enterMarkets(marketToEnter);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();

        ICToken poolToken = ICToken(_poolTokenAddress);

        // Same initial index as Compound.
        uint256 initialIndex;
        if (_poolTokenAddress == cEth) initialIndex = 2e26;
        else initialIndex = 2 * 10**(16 + ERC20(poolToken.underlying()).decimals() - 8);
        p2pSupplyIndex[_poolTokenAddress] = initialIndex;
        p2pBorrowIndex[_poolTokenAddress] = initialIndex;

        Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastUpdateBlockNumber = uint32(block.number);
        poolIndexes.lastSupplyPoolIndex = uint112(poolToken.exchangeRateCurrent());
        poolIndexes.lastBorrowPoolIndex = uint112(poolToken.borrowIndex());

        marketsCreated.push(_poolTokenAddress);
        emit MarketCreated(_poolTokenAddress);
    }
}
