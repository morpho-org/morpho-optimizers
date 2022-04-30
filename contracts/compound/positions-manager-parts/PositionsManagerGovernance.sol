// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerEventsErrors.sol";

/// @title PositionsManagerGovernance.
/// @notice Governance functions for the PositionsManager.
abstract contract PositionsManagerGovernance is PositionsManagerEventsErrors {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// MODIFIERS ///

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPaused(address _poolTokenAddress) {
        if (!marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        if (pauseStatuses[_poolTokenAddress].isPaused) revert MarketPaused();
        _;
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused or partial paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPausedOrPartiallyPaused(address _poolTokenAddress) {
        if (!marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        if (
            pauseStatuses[_poolTokenAddress].isPaused ||
            pauseStatuses[_poolTokenAddress].isPartiallyPaused
        ) revert MarketPaused();
        _;
    }

    /// @notice Prevents a user to call function only allowed for the markets manager.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManager)) revert OnlyMarketsManager();
        _;
    }

    /// GOVERNANCE ///

    /// @notice Sets `maxSortedUsers`.
    /// @param _newMaxSortedUsers The new `maxSortedUsers` value.
    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external onlyOwner {
        maxSortedUsers = _newMaxSortedUsers;
        emit MaxSortedUsersSet(_newMaxSortedUsers);
    }

    /// @notice Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(MaxGas memory _maxGas) external onlyOwner {
        maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _newIncentivesVault The address of the new `incentivesVault`.
    function setIncentivesVault(address _newIncentivesVault) external onlyOwner {
        incentivesVault = IIncentivesVault(_newIncentivesVault);
        emit IncentivesVaultSet(_newIncentivesVault);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyOwner {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @dev Sets `dustThreshold`.
    /// @param _dustThreshold The new `dustThreshold`.
    function setDustThreshold(uint256 _dustThreshold) external onlyOwner {
        dustThreshold = _dustThreshold;
        emit DustThresholdSet(_dustThreshold);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !isCompRewardsActive;
        isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// @notice Toggles the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function togglePauseStatus(address _poolTokenAddress) external onlyOwner {
        PauseStatuses storage pauseStatuses = pauseStatuses[_poolTokenAddress];
        bool newPauseStatus = !pauseStatuses.isPaused;
        pauseStatuses.isPaused = newPauseStatus;
        emit PauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to partially pause/unpause.
    function togglePartialPauseStatus(address _poolTokenAddress) external onlyOwner {
        PauseStatuses storage pauseStatuses = pauseStatuses[_poolTokenAddress];
        bool newPauseStatus = !pauseStatuses.isPartiallyPaused;
        pauseStatuses.isPartiallyPaused = newPauseStatus;
        emit PartialPauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Creates markets.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @return The results of entered.
    function createMarket(address _poolTokenAddress)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        return comptroller.enterMarkets(marketToEnter);
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @dev No more than 90% of the accumulated fees are claimable at once.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
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

        uint256 amountToClaim = Math.min(_amount, (underlyingBalance * 9_000) / MAX_BASIS_POINTS);

        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }
}
