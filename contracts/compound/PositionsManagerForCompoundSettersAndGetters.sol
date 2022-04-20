// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./libraries/LibPositionsManager.sol";
import "./libraries/LibMarketsManager.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/LibStorage.sol";

import "./PositionsManagerForCompoundEventsErrors.sol";

contract PositionsManagerForCompoundSettersAndGetters is
    PositionsManagerForCompoundEventsErrors,
    WithStorageAndModifiers
{
    using SafeTransferLib for ERC20;

    /// SETTERS ///

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

    /// @notice Sets the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function setPauseStatus(address _poolTokenAddress) external onlyOwner {
        bool newPauseStatus = !ps().paused[_poolTokenAddress];
        ps().paused[_poolTokenAddress] = newPauseStatus;
        emit PauseStatusSet(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !ps().isCompRewardsActive;
        ps().isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// GETTERS ///

    function supplyBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_)
    {
        inP2P_ = ps().supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        onPool_ = ps().supplyBalanceInOf[_poolTokenAddress][_user].onPool;
    }

    function borrowBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_)
    {
        inP2P_ = ps().borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        onPool_ = ps().borrowBalanceInOf[_poolTokenAddress][_user].onPool;
    }

    /// @dev Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress) external onlyOwner {
        if (!ms().isCreated[_poolTokenAddress]) revert MarketNotCreated();
        if (ps().paused[_poolTokenAddress]) revert MarketPaused();
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
            ms().comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(ms().comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(ps().incentivesVault), amountOfRewards);
                ps().incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }
}
