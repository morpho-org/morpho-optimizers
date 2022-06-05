// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This abstract contract is a based for rewards managers used to manage the rewards from the Aave protocol.
abstract contract RewardsManager is IRewardsManager, Ownable {
    /// STORAGE ///

    mapping(address => RewardsDataTypes.AssetData) internal localAssetData; // The local data related to a given market.

    IRewardsController public override rewardsController;
    IMorpho public immutable morpho;
    IPool public immutable pool;

    /// EVENTS ///

    /// @notice Emitted the address of the `rewardsController` is set.
    /// @param _rewardsController The new address of the `rewardsController`.
    event RewardsControllerControllerSet(address indexed _rewardsController);

    /**
     * @dev Emitted when rewards of an asset are accrued on behalf of a user.
     * @param asset The address of the incentivized asset
     * @param reward The address of the reward token
     * @param user The address of the user that rewards are accrued on behalf of
     * @param assetIndex The index of the asset distribution
     * @param userIndex The index of the asset distribution on behalf of the user
     * @param rewardsAccrued The amount of rewards accrued
     */
    event Accrued(
        address indexed asset,
        address indexed reward,
        address indexed user,
        uint256 assetIndex,
        uint256 userIndex,
        uint256 rewardsAccrued
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

    /// @notice Constructs the RewardsManager contract.
    /// @param _pool The `pool`.
    /// @param _morpho The `morpho` main contract.
    constructor(IPool _pool, IMorpho _morpho) {
        pool = _pool;
        morpho = _morpho;
    }

    /// EXTERNAL ///

    /// @notice Sets the `rewardsController`.
    /// @param _rewardsController The address of the `rewardsController`.
    function setRewardsController(address _rewardsController) external override onlyOwner {
        rewardsController = IRewardsController(_rewardsController);
        emit RewardsControllerControllerSet(_rewardsController);
    }

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return rewardsList
    /// @return claimedAmounts
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
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    /// @param _totalSupply The total balance of tokens in the distribution.
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalSupply
    ) external override onlyMorpho {
        _updateData(_user, _asset, _userBalance, _totalSupply);
    }

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

    function getAllUserRewards(address[] calldata _assets, address _user)
        external
        view
        override
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts)
    {
        RewardsDataTypes.UserAssetBalance[] memory userAssetBalances = _getUserAssetBalances(
            _assets,
            _user
        );
        rewardsList = rewardsController.getRewardsList();
        uint256 rewardsListLength = rewardsList.length;
        unclaimedAmounts = new uint256[](rewardsListLength);

        // Add unrealized rewards from user to unclaimedRewards.
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
        return (rewardsList, unclaimedAmounts);
    }

    function getUserRewards(
        address[] calldata _assets,
        address _user,
        address _reward
    ) external view override returns (uint256) {
        return _getUserReward(_user, _reward, _getUserAssetBalances(_assets, _user));
    }

    /// PUBLIC ///

    function getUserAssetIndex(
        address _user,
        address _asset,
        address _reward
    ) public view override returns (uint256) {
        return localAssetData[_asset].rewards[_reward].usersData[_user].index;
    }

    /// INTERNAL ///

    /**
     * @dev Updates the state of the distribution for the specified reward
     * @param _totalSupply Current total of underlying assets for this distribution
     * @param _assetUnit One unit of asset (10**decimals)
     * @return newIndex The new distribution index
     * @return indexUpdated True if the index was updated, false otherwise
     **/
    function _updateRewardData(
        RewardsDataTypes.RewardData storage localRewardData,
        address _asset,
        address _reward,
        uint256 _totalSupply,
        uint256 _assetUnit
    ) internal returns (uint256 newIndex, bool indexUpdated) {
        uint256 oldIndex;
        (oldIndex, newIndex) = _getAssetIndex(
            localRewardData,
            _asset,
            _reward,
            _totalSupply,
            _assetUnit
        );

        if (newIndex != oldIndex) {
            require(newIndex <= type(uint104).max, "INDEX_OVERFLOW");

            indexUpdated = true;

            // Optimization: storing one after another saves one SSTORE.
            localRewardData.index = uint104(newIndex);
            localRewardData.lastUpdateTimestamp = uint32(block.timestamp);
        } else localRewardData.lastUpdateTimestamp = uint32(block.timestamp);

        return (newIndex, indexUpdated);
    }

    /**
     * @dev Updates the state of the distribution for the specific _user
     * @param _user The address of the _user
     * @param _userBalance The _user balance of the asset
     * @param _newAssetIndex The new index of the asset distribution
     * @param _assetUnit One unit of asset (10**decimals)
     * @return rewardsAccrued The rewards accrued since the last update
     * @return dataUpdated updated?
     **/
    function _updateUserData(
        RewardsDataTypes.RewardData storage _localRewardData,
        address _user,
        uint256 _userBalance,
        uint256 _newAssetIndex,
        uint256 _assetUnit
    ) internal returns (uint256 rewardsAccrued, bool dataUpdated) {
        uint256 _userIndex = _localRewardData.usersData[_user].index;

        if ((dataUpdated = _userIndex != _newAssetIndex)) {
            // Already checked for overflow in _updateRewardData.
            _localRewardData.usersData[_user].index = uint104(_newAssetIndex);

            if (_userBalance != 0) {
                rewardsAccrued = _getRewards(_userBalance, _newAssetIndex, _userIndex, _assetUnit);

                _localRewardData.usersData[_user].accrued += uint128(rewardsAccrued);
            }
        }
        return (rewardsAccrued, dataUpdated);
    }

    /**
     * @dev Iterates and accrues all the rewards for asset of the specific _user
     * @param _asset The address of the reference asset of the distribution
     * @param _user The _user address
     * @param _userBalance The current _user asset balance
     * @param _totalSupply Total supply of the asset
     **/
    function _updateData(
        address _asset,
        address _user,
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

    /**
     * @dev Accrues all the rewards of the assets specified in the userAssetBalances list
     * @param _user The address of the _user
     * @param _userAssetBalances List of structs with the _user balance and total supply of a set of assets
     **/
    function _updateDataMultiple(
        address _user,
        RewardsDataTypes.UserAssetBalance[] memory _userAssetBalances
    ) internal {
        uint256 userAssetBalancesLength = _userAssetBalances.length;
        for (uint256 i; i < userAssetBalancesLength; ) {
            _updateData(
                _userAssetBalances[i].asset,
                _user,
                _userAssetBalances[i].userBalance,
                _userAssetBalances[i].totalSupply
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Return the accrued unclaimed amount of a reward from a _user over a list of distribution
     * @param _user The address of the _user
     * @param _reward The address of the reward token
     * @param _userAssetBalances List of structs with the _user balance and total supply of a set of assets
     * @return unclaimedRewards The accrued rewards for the _user until the moment
     **/
    function _getUserReward(
        address _user,
        address _reward,
        RewardsDataTypes.UserAssetBalance[] memory _userAssetBalances
    ) internal view returns (uint256 unclaimedRewards) {
        // Add unrealized rewards.
        uint256 userAssetBalancesLength = _userAssetBalances.length;

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

    /**
     * @dev Calculates the pending (not yet accrued) rewards since the last _user action
     * @param _user The address of the _user
     * @param _reward The address of the reward token
     * @param _userAssetBalance struct with the _user balance and total supply of the incentivized asset
     * @return The pending rewards for the _user since the last _user action
     **/
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

    /**
     * @dev Internal function for the calculation of _user's rewards on a distribution
     * @param _userBalance Balance of the _user asset on a distribution
     * @param _reserveIndex Current index of the distribution
     * @param _userIndex Index stored for the _user, representation his staking moment
     * @param _assetUnit One unit of asset (10**decimals)
     * @return rewards The rewards
     **/
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

    /**
     * @dev Calculates the next value of an specific distribution index, with validations
     * @param _totalSupply of the asset being rewarded
     * @param _assetUnit One unit of asset (10**decimals)
     * @return The new index.
     **/
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
                uint256 oldIndex,
                uint256 distributionEnd,
                uint256 emissionPerSecond,
                uint256 lastUpdateTimestamp
            ) = rewardsController.getRewardsData(_asset, _reward);

            if (
                emissionPerSecond == 0 ||
                _totalSupply == 0 ||
                lastUpdateTimestamp == currentTimestamp ||
                lastUpdateTimestamp >= distributionEnd
            ) return (oldIndex, oldIndex);

            currentTimestamp = currentTimestamp > distributionEnd
                ? distributionEnd
                : currentTimestamp;
            uint256 firstTerm = emissionPerSecond *
                (currentTimestamp - lastUpdateTimestamp) *
                _assetUnit;
            assembly {
                firstTerm := div(firstTerm, _totalSupply)
            }
            return (oldIndex, (firstTerm + oldIndex));
        }
    }

    /**
     * @dev Get user balances and total supply of all the assets specified by the assets parameter
     * @param _assets List of assets to retrieve user balance and total supply
     * @param _user Address of the user
     * @return userAssetBalances contains a list of structs with user balance and total supply of the given assets
     */
    function _getUserAssetBalances(address[] calldata _assets, address _user)
        internal
        view
        returns (RewardsDataTypes.UserAssetBalance[] memory userAssetBalances)
    {
        uint256 assetsLength = _assets.length;
        userAssetBalances = new RewardsDataTypes.UserAssetBalance[](assetsLength);

        for (uint256 i = 0; i < assetsLength; i++) {
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
