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
    /// Structs ///

    struct LocalAssetData {
        uint256 lastIndex; // The last index for the given market.
        uint256 lastUpdateTimestamp; // The last time the index has been updated for the given market.
        mapping(address => uint256) userIndex; // The current index for a given user.
    }

    /// Storage ///

    mapping(address => uint256) public userUnclaimedRewards; // The unclaimed rewards of the user.
    mapping(address => LocalAssetData) public localAssetData; // The local data related to a given market.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.

    IAaveIncentivesController public aaveIncentivesController;
    ILendingPoolAddressesProvider public addressesProvider;
    IProtocolDataProvider public dataProvider;
    IPositionsManagerForAave public positionsManager;

    /// Errors ///

    /// @notice Emitted when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// Modifiers ///

    /// @dev Prevents a user to call function allowed for the positions manager only.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// Constructor ///

    /// @dev Constructs the RewardsManager contract.
    /// @param _lendingPoolAddressesProvider The address of the lending pool addresses provider.
    /// @param _positionsManagerAddress The address of the positions manager.
    constructor(address _lendingPoolAddressesProvider, address _positionsManagerAddress) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        aaveIncentivesController = IAaveIncentivesController(
            0x357D51124f59836DeD84c8a1730D72B749d8BC23
        );
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        positionsManager = IPositionsManagerForAave(_positionsManagerAddress);
    }

    /// External ///

    /// @dev Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _amount The amount of token rewards to claim.
    /// @param _user The address of the user.
    function claimRewards(
        address[] calldata _assets,
        uint256 _amount,
        address _user
    ) external onlyPositionsManager returns (uint256 amountToClaim) {
        if (_amount == 0) return 0;

        uint256 unclaimedRewards = getUserUnclaimedRewards(_assets, _user);
        if (unclaimedRewards == 0) return 0;

        amountToClaim = _amount > unclaimedRewards ? unclaimedRewards : _amount;
        userUnclaimedRewards[_user] = unclaimedRewards - amountToClaim;
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

    /// Public ///

    /// @dev Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _assets, address _user)
        public
        returns (uint256)
    {
        uint256 unclaimedRewards = userUnclaimedRewards[_user];
        uint256 accruedRewards;

        for (uint256 i = 0; i < _assets.length; i++) {
            (address aTokenAddress, , address variableDebtTokenAddress) = dataProvider
                .getReserveTokensAddresses(
                IGetterUnderlyingAsset(_assets[i]).UNDERLYING_ASSET_ADDRESS()
            );
            address underlyingAsset = _assets[i];
            uint256 stakedByUser = variableDebtTokenAddress == underlyingAsset
                ? positionsManager.borrowBalanceInOf(aTokenAddress, _user).onPool
                : positionsManager.supplyBalanceInOf(aTokenAddress, _user).onPool;
            uint256 totalStaked = IScaledBalanceToken(underlyingAsset).scaledTotalSupply();

            accruedRewards += _updateUserAsset(_user, underlyingAsset, stakedByUser, totalStaked);
        }

        return unclaimedRewards + accruedRewards;
    }

    /// Internal ///

    /// @dev Updates the state of an user in a distribution.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _stakedByUser The amount of tokens staked by the user in the distribution at the moment.
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return accruedRewards The accrued rewards for the user until the moment.
    function _updateUserAsset(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) internal returns (uint256 accruedRewards) {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 formerUserIndex = localData.userIndex[_user];
        uint256 newIndex = _getUpdatedIndex(_asset, _totalStaked);

        if (formerUserIndex != newIndex) {
            if (_stakedByUser != 0)
                accruedRewards = _getRewards(_stakedByUser, newIndex, formerUserIndex);

            localData.userIndex[_user] = newIndex;
        }
    }

    /// @dev Returns the next reward index.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return newIndex The new distribution index.
    function _getUpdatedIndex(address _asset, uint256 _totalStaked)
        internal
        returns (uint256 newIndex)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 blockTimestamp = block.timestamp;
        uint256 lastTimestamp = localData.lastUpdateTimestamp;

        if (blockTimestamp == lastTimestamp) return localData.lastIndex;
        else {
            IAaveIncentivesController.AssetData memory assetData = aaveIncentivesController.assets(
                _asset
            );
            uint256 oldIndex = assetData.index;
            uint128 lastTimestampOnAave = assetData.lastUpdateTimestamp;

            if (blockTimestamp == lastTimestampOnAave) newIndex = oldIndex;
            else
                newIndex = _getAssetIndex(
                    oldIndex,
                    assetData.emissionPerSecond,
                    lastTimestampOnAave,
                    _totalStaked
                );

            localData.lastUpdateTimestamp = blockTimestamp;
            localData.lastIndex = newIndex;
        }
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
