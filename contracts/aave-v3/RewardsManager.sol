// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/aave/IPoolToken.sol";
import "./interfaces/aave/IPool.sol";
import "./interfaces/IMorpho.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Contract managing Aave's protocol rewards.
contract RewardsManager is IRewardsManager, OwnableUpgradeable {
    /// STRUCTS ///

    struct UserAssetBalance {
        address asset; // The rewarded asset (either aToken or debt token).
        uint256 balance; // The user balance of this asset (in asset decimals).
        uint256 totalSupply; // The total supply of this asset.
    }

    struct UserData {
        uint128 index; // The user's index for a specific (asset, reward) pair.
        uint128 accrued; // The user's accrued rewards for a specific (asset, reward) pair (in reward token decimals).
    }

    struct RewardData {
        uint128 index; // The current index for a specific reward token.
        uint128 lastUpdateTimestamp; // The last timestamp the index was updated.
        mapping(address => UserData) usersData; // Users data. user -> UserData
    }

    /// STORAGE ///

    mapping(address => mapping(address => RewardData)) internal localAssetData; // The local data related to a given asset (either aToken or debt token). asset -> reward -> RewardData

    IMorpho public morpho;
    IPool public pool;

    /// EVENTS ///

    /// @dev Emitted when rewards of an asset are accrued on behalf of a user.
    /// @param _asset The address of the incentivized asset.
    /// @param _reward The address of the reward token.
    /// @param _user The address of the user that rewards are accrued on behalf of.
    /// @param _assetIndex The reward index for the asset (same as the user's index for this asset when the event is logged).
    /// @param _rewardsAccrued The amount of rewards accrued.
    event Accrued(
        address indexed _asset,
        address indexed _reward,
        address indexed _user,
        uint256 _assetIndex,
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

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _rewardsController The rewards controller used to query active rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return rewardsList The list of reward tokens.
    /// @return claimedAmounts The list of claimed reward amounts.
    function claimRewards(
        IRewardsController _rewardsController,
        address[] calldata _assets,
        address _user
    ) external onlyMorpho returns (address[] memory rewardsList, uint256[] memory claimedAmounts) {
        rewardsList = _rewardsController.getRewardsList();
        claimedAmounts = new uint256[](rewardsList.length);

        _updateDataMultiple(_rewardsController, _user, _getUserAssetBalances(_assets, _user));

        for (uint256 i; i < _assets.length; ) {
            address asset = _assets[i];

            for (uint256 j; j < rewardsList.length; ) {
                uint256 rewardAmount = localAssetData[asset][rewardsList[j]]
                .usersData[_user]
                .accrued;

                if (rewardAmount != 0) {
                    claimedAmounts[j] += rewardAmount;
                    localAssetData[asset][rewardsList[j]].usersData[_user].accrued = 0;
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
    /// @param _rewardsController The rewards controller used to query active rewards.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The current user asset balance.
    /// @param _totalSupply The current total supply of underlying assets for this distribution.
    function updateUserAssetAndAccruedRewards(
        IRewardsController _rewardsController,
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalSupply
    ) external onlyMorpho {
        _updateData(_rewardsController, _user, _asset, _userBalance, _totalSupply);
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
            totalAccrued += localAssetData[_assets[i]][_reward].usersData[_user].accrued;

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
        UserAssetBalance[] memory userAssetBalances = _getUserAssetBalances(_assets, _user);
        rewardsList = morpho.rewardsController().getRewardsList();
        uint256 rewardsListLength = rewardsList.length;
        unclaimedAmounts = new uint256[](rewardsListLength);

        // Add unrealized rewards from user to unclaimed rewards.
        for (uint256 i; i < userAssetBalances.length; ) {
            for (uint256 j; j < rewardsListLength; ) {
                unclaimedAmounts[j] += localAssetData[userAssetBalances[i].asset][rewardsList[j]]
                .usersData[_user]
                .accrued;

                if (userAssetBalances[i].balance == 0) continue;

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
        return localAssetData[_asset][_reward].usersData[_user].index;
    }

    /// INTERNAL ///

    /// @dev Updates the state of the distribution for the specified reward.
    /// @param _localRewardData The local reward's data.
    /// @param _asset The asset being rewarded.
    /// @param _reward The address of the reward token.
    /// @param _totalSupply The current total supply of underlying assets for this distribution.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return newIndex The new distribution index.
    /// @return indexUpdated True if the index was updated, false otherwise.
    function _updateRewardData(
        RewardData storage _localRewardData,
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
            require(newIndex <= type(uint128).max, "INDEX_OVERFLOW");

            indexUpdated = true;

            // Optimization: storing one after another saves one SSTORE.
            _localRewardData.index = uint128(newIndex);
        }

        _localRewardData.lastUpdateTimestamp = uint128(block.timestamp);

        return (newIndex, indexUpdated);
    }

    /// @dev Updates the state of the distribution for the specific user.
    /// @param _localRewardData The local reward's data
    /// @param _user The address of the user.
    /// @param _userBalance The current user asset balance.
    /// @param _newAssetIndex The new index of the asset distribution.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return rewardsAccrued The rewards accrued since the last update.
    /// @return dataUpdated True if the data was updated, false otherwise.
    function _updateUserData(
        RewardData storage _localRewardData,
        address _user,
        uint256 _userBalance,
        uint256 _newAssetIndex,
        uint256 _assetUnit
    ) internal returns (uint256 rewardsAccrued, bool dataUpdated) {
        uint256 userIndex = _localRewardData.usersData[_user].index;

        if ((dataUpdated = userIndex != _newAssetIndex)) {
            // Already checked for overflow in _updateRewardData.
            _localRewardData.usersData[_user].index = uint128(_newAssetIndex);

            if (_userBalance != 0) {
                rewardsAccrued = _getRewards(_userBalance, _newAssetIndex, userIndex, _assetUnit);

                // Not safe casting because 2^128 is large enough.
                _localRewardData.usersData[_user].accrued += uint128(rewardsAccrued);
            }
        }
    }

    /// @dev Iterates and accrues all the rewards for asset of the specific user.
    /// @param _rewardsController The rewards controller used to query active rewards.
    /// @param _user The user address.
    /// @param _asset The address of the reference asset of the distribution.
    /// @param _userBalance The current user asset balance.
    /// @param _totalSupply The total supply of the asset.
    function _updateData(
        IRewardsController _rewardsController,
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalSupply
    ) internal {
        address[] memory availableRewards = _rewardsController.getRewardsByAsset(_asset);
        if (availableRewards.length == 0) return;

        unchecked {
            uint256 assetUnit = 10**_rewardsController.getAssetDecimals(_asset);

            for (uint128 i; i < availableRewards.length; ++i) {
                address reward = availableRewards[i];
                RewardData storage localRewardData = localAssetData[_asset][reward];

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
                    emit Accrued(_asset, reward, _user, newAssetIndex, rewardsAccrued);
            }
        }
    }

    /// @dev Accrues all the rewards of the assets specified in the userAssetBalances list.
    /// @param _user The address of the user.
    /// @param _userAssetBalances The list of structs with the user balance and total supply of a set of assets.
    function _updateDataMultiple(
        IRewardsController _rewardsController,
        address _user,
        UserAssetBalance[] memory _userAssetBalances
    ) internal {
        for (uint256 i; i < _userAssetBalances.length; ) {
            _updateData(
                _rewardsController,
                _user,
                _userAssetBalances[i].asset,
                _userAssetBalances[i].balance,
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
        UserAssetBalance[] memory _userAssetBalances
    ) internal view returns (uint256 unclaimedRewards) {
        uint256 userAssetBalancesLength = _userAssetBalances.length;

        // Add unrealized rewards.
        for (uint256 i; i < userAssetBalancesLength; ) {
            if (_userAssetBalances[i].balance == 0) continue;

            unclaimedRewards +=
                _getPendingRewards(_user, _reward, _userAssetBalances[i]) +
                localAssetData[_userAssetBalances[i].asset][_reward].usersData[_user].accrued;

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
        UserAssetBalance memory _userAssetBalance
    ) internal view returns (uint256) {
        RewardData storage localRewardData = localAssetData[_userAssetBalance.asset][_reward];

        uint256 assetUnit;
        unchecked {
            assetUnit = 10**morpho.rewardsController().getAssetDecimals(_userAssetBalance.asset);
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
                _userAssetBalance.balance,
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
    ) internal pure returns (uint256 rewards) {
        rewards = _userBalance * (_reserveIndex - _userIndex);
        assembly {
            rewards := div(rewards, _assetUnit)
        }
    }

    /// @dev Computes the next value of an specific distribution index, with validations.
    /// @param _localRewardData The local reward's data.
    /// @param _asset The asset being rewarded.
    /// @param _reward The address of the reward token.
    /// @param _totalSupply The current total supply of underlying assets for this distribution.
    /// @param _assetUnit The asset's unit (10**decimals).
    /// @return The former index and the new index in this order.
    function _getAssetIndex(
        RewardData storage _localRewardData,
        address _asset,
        address _reward,
        uint256 _totalSupply,
        uint256 _assetUnit
    ) internal view returns (uint256, uint256) {
        uint256 currentTimestamp = block.timestamp;

        if (currentTimestamp == _localRewardData.lastUpdateTimestamp)
            return (_localRewardData.index, _localRewardData.index);

        (
            uint256 rewardIndex,
            uint256 emissionPerSecond,
            uint256 lastUpdateTimestamp,
            uint256 distributionEnd
        ) = morpho.rewardsController().getRewardsData(_asset, _reward);

        if (
            emissionPerSecond == 0 ||
            _totalSupply == 0 ||
            lastUpdateTimestamp == currentTimestamp ||
            lastUpdateTimestamp >= distributionEnd
        ) return (_localRewardData.index, rewardIndex);

        currentTimestamp = currentTimestamp > distributionEnd ? distributionEnd : currentTimestamp;
        uint256 totalEmitted = emissionPerSecond *
            (currentTimestamp - lastUpdateTimestamp) *
            _assetUnit;
        assembly {
            totalEmitted := div(totalEmitted, _totalSupply)
        }
        return (_localRewardData.index, (totalEmitted + rewardIndex));
    }

    /// @dev Returns user balances and total supply of all the assets specified by the assets parameter.
    /// @param _assets List of assets to retrieve user balance and total supply.
    /// @param _user The address of the user.
    /// @return userAssetBalances The list of structs with user balance and total supply of the given assets.
    function _getUserAssetBalances(address[] calldata _assets, address _user)
        internal
        view
        returns (UserAssetBalance[] memory userAssetBalances)
    {
        uint256 assetsLength = _assets.length;
        userAssetBalances = new UserAssetBalance[](assetsLength);

        for (uint256 i; i < assetsLength; ) {
            address asset = _assets[i];
            userAssetBalances[i].asset = asset;

            DataTypes.ReserveData memory reserve = pool.getReserveData(
                IPoolToken(userAssetBalances[i].asset).UNDERLYING_ASSET_ADDRESS()
            );

            if (asset == reserve.aTokenAddress)
                userAssetBalances[i].balance = morpho
                .supplyBalanceInOf(reserve.aTokenAddress, _user)
                .onPool;
            else if (asset == reserve.variableDebtTokenAddress)
                userAssetBalances[i].balance = morpho
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
