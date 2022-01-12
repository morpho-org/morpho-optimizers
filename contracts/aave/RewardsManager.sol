// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";

import {DistributionTypes} from "./libraries/aave/DistributionTypes.sol";

contract RewardsManager {
    /// Storage ///

    mapping(address => mapping(address => uint256)) public userIndex; // The reward index related to an asset for a given user.
    mapping(address => uint256) public userUnclaimedRewards; // The unclaimed rewards of the user.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.

    IAaveIncentivesController public aaveIncentivesController;
    ILendingPoolAddressesProvider public addressesProvider;
    IProtocolDataProvider public dataProvider;
    IPositionsManagerForAave public positionsManager;

    error OnlyPositionsManager();

    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    constructor(address _lendingPoolAddressesProvider, address _positionsManagerAddress) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        aaveIncentivesController = IAaveIncentivesController(
            0x357D51124f59836DeD84c8a1730D72B749d8BC23
        );
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        positionsManager = IPositionsManagerForAave(_positionsManagerAddress);
    }

    /// @dev Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    function accrueRewardsForAssetsBeforeClaiming(
        address[] calldata _assets,
        uint256 _amount,
        address _user
    ) external onlyPositionsManager returns (uint256) {
        if (_amount == 0) return 0;
        uint256 unclaimedRewards = userUnclaimedRewards[_user];


            DistributionTypes.UserStakeInput[] memory userState
         = new DistributionTypes.UserStakeInput[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            (address aTokenAddress, , address variableDebtTokenAddress) = dataProvider
                .getReserveTokensAddresses(
                IGetterUnderlyingAsset(_assets[i]).UNDERLYING_ASSET_ADDRESS()
            );
            userState[i].underlyingAsset = _assets[i];
            userState[i].stakedByUser = variableDebtTokenAddress == _assets[i]
                ? positionsManager.borrowBalanceInOf(aTokenAddress, _user).onPool
                : positionsManager.supplyBalanceInOf(aTokenAddress, _user).onPool;
            userState[i].totalStaked = IScaledBalanceToken(_assets[i]).scaledTotalSupply();
        }

        uint256 accruedRewards = _computeAccruedRewards(_user, userState);
        if (accruedRewards != 0) {
            unclaimedRewards = unclaimedRewards + accruedRewards;
            userUnclaimedRewards[_user] = unclaimedRewards;
        }
        if (unclaimedRewards == 0) return 0;

        uint256 amountToClaim = _amount > unclaimedRewards ? unclaimedRewards : _amount;
        userUnclaimedRewards[_user] = userUnclaimedRewards[_user] - amountToClaim;

        return amountToClaim;
    }

    /// @dev Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _stakedByUser The amount of tokens staked by the user in the distribution at the moment.
    /// @param _totalStaked The total of tokens staked in the distribution.
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) external onlyPositionsManager {
        userUnclaimedRewards[_user] += _updateUserAsset(_user, _asset, _stakedByUser, _totalStaked);
    }

    /// @dev Updates the state of an user in several distribution and returns the total accrued rewards.
    /// @param _user The address of the user.
    /// @param _stakes The different staking positions of the user to update and their data.
    /// @return The accrued rewards for the user until the moment.
    function _computeAccruedRewards(
        address _user,
        DistributionTypes.UserStakeInput[] memory _stakes
    ) internal returns (uint256) {
        uint256 accruedRewards;

        for (uint256 i = 0; i < _stakes.length; i++) {
            accruedRewards =
                accruedRewards +
                _updateUserAsset(
                    _user,
                    _stakes[i].underlyingAsset,
                    _stakes[i].stakedByUser,
                    _stakes[i].totalStaked
                );
        }

        return accruedRewards;
    }

    /// @dev Updates the state of an user in a distribution.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _stakedByUser The amount of tokens staked by the user in the distribution at the moment.
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return The accrued rewards for the user until the moment.
    function _updateUserAsset(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) internal returns (uint256) {
        IAaveIncentivesController.AssetData memory assetData = aaveIncentivesController.assets(
            _asset
        );
        uint256 formerUserIndex = userIndex[_asset][_user];
        uint256 accruedRewards;
        uint256 newIndex = _getUpdatedIndex(assetData, _totalStaked);

        if (formerUserIndex != newIndex) {
            if (_stakedByUser != 0)
                accruedRewards = _getRewards(_stakedByUser, newIndex, formerUserIndex);

            userIndex[_asset][_user] = newIndex;
        }

        return accruedRewards;
    }

    /// @dev Returns the next reward index.
    /// @param _assetConfig The current config of the asset on Aave.
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return The new distribution index.
    function _getUpdatedIndex(
        IAaveIncentivesController.AssetData memory _assetConfig,
        uint256 _totalStaked
    ) internal view returns (uint256) {
        uint256 oldIndex = _assetConfig.index;
        uint128 lastUpdateTimestamp = _assetConfig.lastUpdateTimestamp;

        if (block.timestamp == lastUpdateTimestamp) return oldIndex;
        return
            _getAssetIndex(
                oldIndex,
                _assetConfig.emissionPerSecond,
                lastUpdateTimestamp,
                _totalStaked
            );
    }

    /// @dev Computes and returns the next value of a specific distribution index.
    /// @param _currentIndex The current index of the distribution.
    /// @param _emissionPerSecond The total rewards distributed per second per asset unit, on the distribution.
    /// @param _lastUpdateTimestamp The last moment this distribution was updated.
    /// @param _totalBalance The total balance of tokens considered for the distribution.
    /// @return The new index.
    function _getAssetIndex(
        uint256 _currentIndex,
        uint256 _emissionPerSecond,
        uint128 _lastUpdateTimestamp,
        uint256 _totalBalance
    ) internal view returns (uint256) {
        uint256 distributionEnd = aaveIncentivesController.DISTRIBUTION_END();
        if (
            _emissionPerSecond == 0 ||
            _totalBalance == 0 ||
            _lastUpdateTimestamp == block.timestamp ||
            _lastUpdateTimestamp >= distributionEnd
        ) {
            return _currentIndex;
        }

        uint256 currentTimestamp = block.timestamp > distributionEnd
            ? distributionEnd
            : block.timestamp;
        uint256 timeDelta = currentTimestamp - _lastUpdateTimestamp;
        return ((_emissionPerSecond * timeDelta * 1e18) / _totalBalance) + _currentIndex;
    }

    /// @dev Computes and returns the rewards on a distribution.
    /// @param _principalUserBalance The amount staked by the user on a distribution.
    /// @param _reserveIndex The current index of the distribution.
    /// @param _userIndex The index stored for the user, representing his staking moment.
    /// @return The rewards.
    function _getRewards(
        uint256 _principalUserBalance,
        uint256 _reserveIndex,
        uint256 _userIndex
    ) internal pure returns (uint256) {
        return (_principalUserBalance * (_reserveIndex - _userIndex)) / 1e18;
    }
}
