// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./libraries/LibPositionsManagerGetters.sol";
import "./libraries/LibStorage.sol";

contract PositionsManagerForCompoundGovernor is WithStorageAndModifiers {
    using SafeTransferLib for ERC20;

    /// EVENTS ///

    /// @notice Emitted when a new value for `NDS` is set.
    /// @param _newValue The new value of `NDS`.
    event NDSSet(uint8 _newValue);

    /// @notice Emitted when a new `maxGas` is set.
    /// @param _maxGas The new `maxGas`.
    event MaxGasSet(Types.MaxGas _maxGas);

    /// @notice Emitted the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address indexed _newTreasuryVaultAddress);

    /// @notice Emitted the address of the `incentivesVault` is set.
    /// @param _newIncentivesVaultAddress The new address of the `incentivesVault`.
    event IncentivesVaultSet(address indexed _newIncentivesVaultAddress);

    /// @notice Emitted the address of the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address indexed _newRewardsManagerAddress);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the pool token concerned.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address indexed _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a COMP reward status is changed.
    /// @param _isCompRewardsActive The new COMP reward status.
    event CompRewardsActive(bool _isCompRewardsActive);

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address indexed _user, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards and converts them to Morpho tokens.
    /// @param _user The address of the claimer.
    /// @param _amountSent The amount of reward token sent to the vault.
    event RewardsClaimedAndConverted(address indexed _user, uint256 _amountSent);

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();

    /// EXTERNAL ///

    /// @notice Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyOwner {
        ps().NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @notice Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(Types.MaxGas memory _maxGas) external onlyOwner {
        ps().maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyOwner {
        ps().treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _newIncentivesVault The address of the new `incentivesVault`.
    function setIncentivesVault(address _newIncentivesVault) external onlyOwner {
        ps().incentivesVault = IIncentivesVault(_newIncentivesVault);
        emit IncentivesVaultSet(_newIncentivesVault);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyOwner {
        ps().rewardsManager = IRewardsManagerForCompound(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !ps().isCompRewardsActive;
        ps().isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress) external onlyOwner {
        MarketsStorage storage m = LibStorage.marketsStorage();
        if (!m.isCreated[_poolTokenAddress]) revert MarketNotCreated();
        if (m.paused[_poolTokenAddress]) revert MarketPaused();
        if (ps().treasuryVault == address(0)) revert ZeroAddress();

        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));

        if (amountToClaim == 0) revert AmountIsZero();

        underlyingToken.safeTransfer(ps().treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _claimMorphoToken Whether or not to claim Morpho tokens instead of token reward.
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken)
        external
        nonReentrant
    {
        uint256 amountOfRewards = ps().rewardsManager.claimRewards(_cTokenAddresses, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();
        else {
            PositionsStorage storage p = ps();
            p.comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(p.comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(p.incentivesVault), amountOfRewards);
                p.incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }
}
