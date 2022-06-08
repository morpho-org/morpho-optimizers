// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Contract managing Aave's protocol rewards.
contract RewardsManager is IRewardsManager, OwnableUpgradeable {
    /// STORAGE ///

    mapping(address => RewardsDataTypes.AssetData) internal localAssetData; // The local data related to a given market.

    IRewardsController public rewardsController;
    IMorpho public morpho;
    IPool public pool;

    /// EVENTS ///

    /// @notice Emitted when the address of the `rewardsController` is set.
    /// @param _rewardsController The new address of the `rewardsController`.
    event RewardsControllerSet(address indexed _rewardsController);

    /// @dev Emitted when rewards of an asset are accrued on behalf of a user.
    /// @param _asset The address of the incentivized asset.
    /// @param _reward The address of the reward token.
    /// @param _user The address of the user that rewards are accrued on behalf of.
    /// @param _assetIndex The index of the asset distribution.
    /// @param _userIndex The index of the asset distribution on behalf of the user.
    /// @param _rewardsAccrued The amount of rewards accrued.
    event Accrued(
        address indexed _asset,
        address indexed _reward,
        address indexed _user,
        uint256 _assetIndex,
        uint256 _userIndex,
        uint256 _rewardsAccrued
    );

    /// ERRORS ///

    /// @notice Thrown when only the main Morpho contract can call the function.
    error OnlyMorpho();

    /// @notice Thrown when an invalid asset is passed to accrue rewards.
    error InvalidAsset();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the main Morpho contract only.
    modifier onlyMorpho() {
        if (msg.sender != address(morpho)) revert OnlyMorpho();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}

    /// UPGRADE ///

    /// @notice Initializes the RewardsManager contract.
    /// @param _morpho The address of Morpho's main contract's proxy.
    function initialize(address _morpho) external initializer {
        __Ownable_init();

        morpho = IMorpho(_morpho);
        pool = IPool(morpho.pool());
    }

    /// EXTERNAL ///

    /// @notice Sets the `rewardsController`.
    /// @param _rewardsController The address of the `rewardsController`.
    function setRewardsController(address _rewardsController) external onlyOwner {
        rewardsController = IRewardsController(_rewardsController);
        emit RewardsControllerSet(_rewardsController);
    }

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return rewardsList The list of reward tokens.
    /// @return claimedAmounts The list of claimed reward amounts.
    function claimRewards(address[] calldata _assets, address _user)
        external
        onlyMorpho
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        rewardsList = rewardsController.getRewardsList();
        uint256 rewardsListLength = rewardsList.length;
        uint256 assetsLength = _assets.length;
        claimedAmounts = new uint256[](rewardsListLength);

        _updateDataMultiple(_user, _getUserAssetBalances(_assets, _user));

        for (uint256 i; i < assetsLength; ) {
            address asset = _assets[i];

            for (uint256 j; j < rewardsListLength; ) {
                uint256 rewardAmount = localAssetData[asset]
                .rewards[rewardsList[j]]
                .usersData[_user]
                .accrued;

                if (rewardAmount != 0) {
                    claimedAmounts[j] += rewardAmount;
                    localAssetData[asset].rewards[rewardsList[j]].usersData[_user].accrued = 0;
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates the unclaimed rewards of a user.
    /// @dev Only called by Morpho at positions updates in the data structure.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The current user asset balance.
    /// @param _totalSupply The current total supply of underlying assets for this distribution.
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalSupply
    ) external onlyMorpho {
        _updateData(_user, _asset, _userBalance, _totalSupply);
    }

    /// @notice Returns user's accrued rewards for the specified assets and reward token
    /// @param _assets The list of assets to retrieve accrued rewards.
    /// @param _user The address of the user.
    /// @return totalAccrued The total amount of accrued rewards.
    function getUserAccruedRewards(
        address[] calldata _assets,
        address _user,
        address _reward
    ) external view returns (uint256 totalAccrued) {
        uint256 assetsLength = _assets.length;

        for (uint256 i; i < assetsLength; ) {
            totalAccrued += localAssetData[_assets[i]].rewards[_reward].usersData[_user].accrued;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns user's rewards for the specified assets and for all reward tokens.
    /// @param _assets The list of assets to retrieve rewards.
    /// @param _user The address of the user.
    /// @return rewardsList The list of reward tokens.
    /// @return unclaimedAmounts The list of unclaimed reward amounts.
    function getAllUserRewards(address[] calldata _assets, address _user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts)
    {
        RewardsDataTypes.UserAssetBalance[] memory userAssetBalances = _getUserAssetBalances(
            _assets,
            _user
        );
        rewardsList = rewardsController.getRewardsList();
        uint256 rewardsListLength = rewardsList.length;
        unclaimedAmounts = new uint256[](rewardsListLength);

        // Add unrealized rewards from user to unclaimed rewards.
        for (uint256 i; i < userAssetBalances.length; ) {
            for (uint256 j; j < rewardsListLength; ) {
                unclaimedAmounts[j] += localAssetData[userAssetBalances[i].asset]
                .rewards[rewardsList[j]]
                .usersData[_user]
                .accrued;

                if (userAssetBalances[i].userBalance == 0) continue;

                unclaimedAmounts[j] += _getPendingRewards(
                    _user,
                    rewardsList[j],
                    userAssetBalances[i]
                );

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns user's rewards for the specified assets and reward token.
    /// @param _assets The list of assets to retrieve rewards.
    /// @param _user The address of the user.
    /// @param _reward The address of the reward token
    /// @return The user's rewards in reward token.
    function getUserRewards(
        address[] calldata _assets,
        address _user,
        address _reward
    ) external view override returns (uint256) {
        return _getUserReward(_user, _reward, _getUserAssetBalances(_assets, _user));
    }

    /// @notice Returns the user's index for the specified asset and reward token.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _reward The address of the reward token.
    /// @return The user's index.
    function getUserAssetIndex(
        address _user,
        address _asset,
        address _reward
    ) external view override returns (uint256) {
        return localAssetData[_asset].rewards[_reward].usersData[_user].index;
    }

    /// INTERNAL ///

    /// @dev Updates the state of the distribution for the specified reward.
    /// @param _totalSupply The current total supply of underlying assets for this distribution.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return newIndex The new distribution index.
    /// @return indexUpdated True if the index was updated, false otherwise.
    function _updateRewardData(
        RewardsDataTypes.RewardData storage _localRewardData,
        address _asset,
        address _reward,
        uint256 _totalSupply,
        uint256 _assetUnit
    ) internal returns (uint256 newIndex, bool indexUpdated) {
        uint256 oldIndex;
        (oldIndex, newIndex) = _getAssetIndex(
            _localRewardData,
            _asset,
            _reward,
            _totalSupply,
            _assetUnit
        );

        if (newIndex != oldIndex) {
            require(newIndex <= type(uint104).max, "INDEX_OVERFLOW");

            indexUpdated = true;

            // Optimization: storing one after another saves one SSTORE.
            _localRewardData.index = uint104(newIndex);
            _localRewardData.lastUpdateTimestamp = uint32(block.timestamp);
        } else _localRewardData.lastUpdateTimestamp = uint32(block.timestamp);

        return (newIndex, indexUpdated);
    }

    /// @dev Updates the state of the distribution for the specific user.
    /// @param _user The address of the user.
    /// @param _userBalance The current user asset balance.
    /// @param _newAssetIndex The new index of the asset distribution.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return rewardsAccrued The rewards accrued since the last update.
    /// @return dataUpdated True if the data was updated, false otherwise.
    function _updateUserData(
        RewardsDataTypes.RewardData storage _localRewardData,
        address _user,
        uint256 _userBalance,
        uint256 _newAssetIndex,
        uint256 _assetUnit
    ) internal returns (uint256 rewardsAccrued, bool dataUpdated) {
        uint256 userIndex = _localRewardData.usersData[_user].index;

        if ((dataUpdated = userIndex != _newAssetIndex)) {
            // Already checked for overflow in _updateRewardData.
            _localRewardData.usersData[_user].index = uint104(_newAssetIndex);

            if (_userBalance != 0) {
                rewardsAccrued = _getRewards(_userBalance, _newAssetIndex, userIndex, _assetUnit);

                _localRewardData.usersData[_user].accrued += uint128(rewardsAccrued);
            }
        }
    }

    /// @dev Iterates and accrues all the rewards for asset of the specific user.
    /// @param _user The user address.
    /// @param _asset The address of the reference asset of the distribution.
    /// @param _userBalance The current user asset balance.
    /// @param _totalSupply The total supply of the asset.
    function _updateData(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalSupply
    ) internal {
        address[] memory availableRewards = rewardsController.getRewardsByAsset(_asset);
        uint256 numAvailableRewards = availableRewards.length;
        if (numAvailableRewards == 0) return;

        unchecked {
            uint256 assetUnit = 10**rewardsController.getAssetDecimals(_asset);

            for (uint128 i; i < numAvailableRewards; ++i) {
                address reward = availableRewards[i];
                RewardsDataTypes.RewardData storage localRewardData = localAssetData[_asset]
                .rewards[reward];

                (uint256 newAssetIndex, bool rewardDataUpdated) = _updateRewardData(
                    localRewardData,
                    _asset,
                    reward,
                    _totalSupply,
                    assetUnit
                );

                (uint256 rewardsAccrued, bool userDataUpdated) = _updateUserData(
                    localRewardData,
                    _user,
                    _userBalance,
                    newAssetIndex,
                    assetUnit
                );

                if (rewardDataUpdated || userDataUpdated)
                    emit Accrued(
                        _asset,
                        reward,
                        _user,
                        newAssetIndex,
                        newAssetIndex,
                        rewardsAccrued
                    );
            }
        }
    }

    /// @dev Accrues all the rewards of the assets specified in the userAssetBalances list.
    /// @param _user The address of the user.
    /// @param _userAssetBalances The list of structs with the user balance and total supply of a set of assets.
    function _updateDataMultiple(
        address _user,
        RewardsDataTypes.UserAssetBalance[] memory _userAssetBalances
    ) internal {
        uint256 userAssetBalancesLength = _userAssetBalances.length;
        for (uint256 i; i < userAssetBalancesLength; ) {
            _updateData(
                _user,
                _userAssetBalances[i].asset,
                _userAssetBalances[i].userBalance,
                _userAssetBalances[i].totalSupply
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns the accrued unclaimed amount of a reward from a user over a list of distribution.
    /// @param _user The address of the user.
    /// @param _reward The address of the reward token.
    /// @param _userAssetBalances List of structs with the user balance and total supply of a set of assets.
    /// @return unclaimedRewards The accrued rewards for the user until the moment.
    function _getUserReward(
        address _user,
        address _reward,
        RewardsDataTypes.UserAssetBalance[] memory _userAssetBalances
    ) internal view returns (uint256 unclaimedRewards) {
        uint256 userAssetBalancesLength = _userAssetBalances.length;

        // Add unrealized rewards.
        for (uint256 i; i < userAssetBalancesLength; ) {
            if (_userAssetBalances[i].userBalance == 0) continue;

            unclaimedRewards +=
                _getPendingRewards(_user, _reward, _userAssetBalances[i]) +
                localAssetData[_userAssetBalances[i].asset]
                .rewards[_reward]
                .usersData[_user]
                .accrued;

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Computes the pending (not yet accrued) rewards since the last user action.
    /// @param _user The address of the user.
    /// @param _reward The address of the reward token.
    /// @param _userAssetBalance The struct with the user balance and total supply of the incentivized asset.
    /// @return The pending rewards for the user since the last user action.
    function _getPendingRewards(
        address _user,
        address _reward,
        RewardsDataTypes.UserAssetBalance memory _userAssetBalance
    ) internal view returns (uint256) {
        RewardsDataTypes.RewardData storage localRewardData = localAssetData[
            _userAssetBalance.asset
        ]
        .rewards[_reward];

        uint256 assetUnit;
        unchecked {
            assetUnit = 10**rewardsController.getAssetDecimals(_userAssetBalance.asset);
        }

        (, uint256 nextIndex) = _getAssetIndex(
            localRewardData,
            _userAssetBalance.asset,
            _reward,
            _userAssetBalance.totalSupply,
            assetUnit
        );

        return
            _getRewards(
                _userAssetBalance.userBalance,
                nextIndex,
                localRewardData.usersData[_user].index,
                assetUnit
            );
    }

    /// @dev Computes user's accrued rewards on a distribution.
    /// @param _userBalance The current user asset balance.
    /// @param _reserveIndex The current index of the distribution.
    /// @param _userIndex The index stored for the user, representing its staking moment.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return rewards The rewards accrued.
    function _getRewards(
        uint256 _userBalance,
        uint256 _reserveIndex,
        uint256 _userIndex,
        uint256 _assetUnit
    ) internal view returns (uint256 rewards) {
        rewards = _userBalance * (_reserveIndex - _userIndex);
        assembly {
            rewards := div(rewards, _assetUnit)
        }
    }

    /// @dev Computes the next value of an specific distribution index, with validations.
    /// @param _totalSupply of the asset being rewarded.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return The former index and the new index in this order.
    function _getAssetIndex(
        RewardsDataTypes.RewardData storage _localRewardData,
        address _asset,
        address _reward,
        uint256 _totalSupply,
        uint256 _assetUnit
    ) internal view returns (uint256, uint256) {
        uint256 currentTimestamp = block.timestamp;

        if (currentTimestamp == _localRewardData.lastUpdateTimestamp)
            return (_localRewardData.index, _localRewardData.index);
        else {
            (
                uint256 rewardIndex,
                uint256 emissionPerSecond,
                uint256 lastUpdateTimestamp,
                uint256 distributionEnd
            ) = rewardsController.getRewardsData(_asset, _reward);

            if (
                emissionPerSecond == 0 ||
                _totalSupply == 0 ||
                lastUpdateTimestamp == currentTimestamp ||
                lastUpdateTimestamp >= distributionEnd
            ) return (_localRewardData.index, rewardIndex);

            currentTimestamp = currentTimestamp > distributionEnd
                ? distributionEnd
                : currentTimestamp;
            uint256 firstTerm = emissionPerSecond *
                (currentTimestamp - lastUpdateTimestamp) *
                _assetUnit;
            assembly {
                firstTerm := div(firstTerm, _totalSupply)
            }
            return (_localRewardData.index, (firstTerm + rewardIndex));
        }
    }

    /// @dev Returns user balances and total supply of all the assets specified by the assets parameter.
    /// @param _assets List of assets to retrieve user balance and total supply.
    /// @param _user The address of the user.
    /// @return userAssetBalances The list of structs with user balance and total supply of the given assets.
    function _getUserAssetBalances(address[] calldata _assets, address _user)
        internal
        view
        returns (RewardsDataTypes.UserAssetBalance[] memory userAssetBalances)
    {
        uint256 assetsLength = _assets.length;
        userAssetBalances = new RewardsDataTypes.UserAssetBalance[](assetsLength);

        for (uint256 i; i < assetsLength; ) {
            address asset = _assets[i];
            userAssetBalances[i].asset = asset;

            DataTypes.ReserveData memory reserve = pool.getReserveData(
                IGetterUnderlyingAsset(userAssetBalances[i].asset).UNDERLYING_ASSET_ADDRESS()
            );

            if (asset == reserve.aTokenAddress)
                userAssetBalances[i].userBalance = morpho
                .supplyBalanceInOf(reserve.aTokenAddress, _user)
                .onPool;
            else if (asset == reserve.variableDebtTokenAddress)
                userAssetBalances[i].userBalance = morpho
                .borrowBalanceInOf(reserve.aTokenAddress, _user)
                .onPool;
            else revert InvalidAsset();

            userAssetBalances[i].totalSupply = IScaledBalanceToken(asset).scaledTotalSupply();

            unchecked {
                ++i;
            }
        }
    }
}
