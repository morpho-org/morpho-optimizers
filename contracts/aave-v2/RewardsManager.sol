// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This abstract contract is a base for rewards managers managing the rewards from the Aave protocol.
abstract contract RewardsManager is IRewardsManager, OwnableUpgradeable {
    /// STRUCTS ///

    struct LocalAssetData {
        uint256 lastIndex; // The last index for the given market.
        uint256 lastUpdateTimestamp; // The last time the index has been updated for the given market.
        mapping(address => uint256) userIndex; // The current index for a given user.
    }

    /// STORAGE ///

    mapping(address => uint256) public userUnclaimedRewards; // The unclaimed rewards of the user.
    mapping(address => LocalAssetData) public localAssetData; // The local data related to a given market.

    IAaveIncentivesController public override aaveIncentivesController;
    ILendingPool public lendingPool;
    IMorpho public morpho;

    /// EVENTS ///

    /// @notice Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address indexed _aaveIncentivesController);

    /// @notice Emitted when rewards of an asset are accrued on behalf of a user.
    /// @param _asset The address of the incentivized asset.
    /// @param _user The address of the user that rewards are accrued on behalf of.
    /// @param _assetIndex The index of the asset distribution.
    /// @param _userIndex The index of the asset distribution on behalf of the user.
    /// @param _rewardsAccrued The amount of rewards accrued.
    event Accrued(
        address indexed _asset,
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
        lendingPool = ILendingPool(morpho.lendingPool());
    }

    /// EXTERNAL ///

    /// @notice Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController)
        external
        override
        onlyOwner
    {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The unclaimed rewards claimed by the user.
    function claimRewards(address[] calldata _assets, address _user)
        external
        override
        onlyMorpho
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = _accrueUserUnclaimedRewards(_assets, _user);
        userUnclaimedRewards[_user] = 0;
    }

    /// @notice Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    /// @param _totalBalance The total balance of tokens in the distribution.
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalBalance
    ) external onlyMorpho {
        userUnclaimedRewards[_user] += _updateUserAsset(_user, _asset, _userBalance, _totalBalance);
    }

    /// @notice Returns the index of the `_user` for a given `_asset`.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return The index of the user.
    function getUserIndex(address _asset, address _user) external view override returns (uint256) {
        return localAssetData[_asset].userIndex[_user];
    }

    /// @notice Get the unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function getUserUnclaimedRewards(address[] calldata _assets, address _user)
        external
        view
        override
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedRewards[_user];

        for (uint256 i; i < _assets.length; ) {
            address asset = _assets[i];
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(
                IGetterUnderlyingAsset(asset).UNDERLYING_ASSET_ADDRESS()
            );
            uint256 userBalance;
            if (asset == reserve.aTokenAddress)
                userBalance = morpho.supplyBalanceInOf(reserve.aTokenAddress, _user).onPool;
            else if (asset == reserve.variableDebtTokenAddress)
                userBalance = morpho.borrowBalanceInOf(reserve.aTokenAddress, _user).onPool;
            else revert InvalidAsset();

            uint256 totalBalance = IScaledBalanceToken(asset).scaledTotalSupply();

            unclaimedRewards += _getUserAsset(_user, asset, userBalance, totalBalance);

            unchecked {
                ++i;
            }
        }
    }

    /// INTERNAL ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function _accrueUserUnclaimedRewards(address[] calldata _assets, address _user)
        internal
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedRewards[_user];
        uint256 assetsLenght = _assets.length;

        for (uint256 i; i < assetsLenght; ) {
            address asset = _assets[i];
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(
                IGetterUnderlyingAsset(asset).UNDERLYING_ASSET_ADDRESS()
            );
            uint256 userBalance;
            if (asset == reserve.aTokenAddress)
                userBalance = morpho.supplyBalanceInOf(reserve.aTokenAddress, _user).onPool;
            else if (asset == reserve.variableDebtTokenAddress)
                userBalance = morpho.borrowBalanceInOf(reserve.aTokenAddress, _user).onPool;
            else revert InvalidAsset();

            uint256 totalBalance = IScaledBalanceToken(asset).scaledTotalSupply();

            unclaimedRewards += _updateUserAsset(_user, asset, userBalance, totalBalance);

            unchecked {
                ++i;
            }
        }

        userUnclaimedRewards[_user] = unclaimedRewards;
    }

    /// @dev Updates asset's data.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _totalBalance The total balance of tokens in the distribution.
    function _udpateAsset(address _asset, uint256 _totalBalance)
        internal
        returns (uint256 oldIndex, uint256 newIndex)
    {
        (oldIndex, newIndex) = _getAssetIndex(_asset, _totalBalance);
        if (oldIndex != newIndex) {
            localAssetData[_asset].lastUpdateTimestamp = block.timestamp;
            localAssetData[_asset].lastIndex = newIndex;
        }
    }

    /// @dev Updates the state of a user in a distribution.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return accruedRewards The accrued rewards for the user until the moment for this asset.
    function _updateUserAsset(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalBalance
    ) internal returns (uint256 accruedRewards) {
        uint256 formerUserIndex = localAssetData[_asset].userIndex[_user];
        (, uint256 newIndex) = _udpateAsset(_asset, _totalBalance);

        if (formerUserIndex != newIndex) {
            if (_userBalance != 0) {}
            accruedRewards = _getRewards(_userBalance, newIndex, formerUserIndex);

            localAssetData[_asset].userIndex[_user] = newIndex;
            emit Accrued(_asset, _user, newIndex, formerUserIndex, accruedRewards);
        }
    }

    /// @dev Gets the state of a user in a distribution.
    /// @dev This function is the equivalent of _updateUserAsset but as a view.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return accruedRewards The accrued rewards for the user until the moment for this asset.
    function _getUserAsset(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalBalance
    ) internal view returns (uint256 accruedRewards) {
        uint256 formerUserIndex = localAssetData[_asset].userIndex[_user];
        (, uint256 newIndex) = _getAssetIndex(_asset, _totalBalance);

        if (formerUserIndex != newIndex && _userBalance != 0)
            accruedRewards = _getRewards(_userBalance, newIndex, formerUserIndex);
    }

    /// @dev Computes and returns the next value of a specific distribution index.
    /// @param _currentIndex The current index of the distribution.
    /// @param _emissionPerSecond The total rewards distributed per second per asset unit, on the distribution.
    /// @param _lastUpdateTimestamp The last moment this distribution was updated.
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return The new index.
    function _computeIndex(
        uint256 _currentIndex,
        uint256 _emissionPerSecond,
        uint256 _lastUpdateTimestamp,
        uint256 _totalBalance
    ) internal view returns (uint256) {
        uint256 distributionEnd = aaveIncentivesController.DISTRIBUTION_END();
        uint256 currentTimestamp = block.timestamp;

        if (
            _lastUpdateTimestamp == currentTimestamp ||
            _emissionPerSecond == 0 ||
            _totalBalance == 0 ||
            _lastUpdateTimestamp >= distributionEnd
        ) return _currentIndex;

        if (currentTimestamp > distributionEnd) currentTimestamp = distributionEnd;
        uint256 timeDelta = currentTimestamp - _lastUpdateTimestamp;
        return ((_emissionPerSecond * timeDelta * 1e18) / _totalBalance) + _currentIndex;
    }

    /// @dev Computes and returns the rewards on a distribution.
    /// @param _userBalance The user balance of tokens in the distribution.
    /// @param _reserveIndex The current index of the distribution.
    /// @param _userIndex The index stored for the user, representing his staking moment.
    /// @return The rewards.
    function _getRewards(
        uint256 _userBalance,
        uint256 _reserveIndex,
        uint256 _userIndex
    ) internal pure returns (uint256) {
        return (_userBalance * (_reserveIndex - _userIndex)) / 1e18;
    }

    /// @dev Returns the next reward index.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return oldIndex The old distribution index.
    /// @return newIndex The new distribution index.
    function _getAssetIndex(address _asset, uint256 _totalBalance)
        internal
        view
        virtual
        returns (uint256 oldIndex, uint256 newIndex);
}
