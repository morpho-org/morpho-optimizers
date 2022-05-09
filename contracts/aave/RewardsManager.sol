// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RewardsManager is IRewardsManager, Ownable {
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
    ILendingPool public immutable lendingPool;
    IMorpho public immutable morpho;
    address public override swapManager;

    /// EVENTS ///

    /// @notice Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address indexed _aaveIncentivesController);

    /// @notice Emitted the address of the `swapManager` is set.
    /// @param _swapManager The new address of the `swapManager`.
    event SwapManagerSet(address indexed _swapManager);

    /// ERRORS ///

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when an invalid asset is passed to accrue rewards.
    error InvalidAsset();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the positions manager only.
    modifier onlyPositionsManager() {
        if (msg.sender != address(morpho)) revert OnlyPositionsManager();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _lendingPool The `lendingPool`.
    /// @param _morpho The `morpho`.
    /// @param _swapManager The address of the `swapManager`.
    constructor(
        ILendingPool _lendingPool,
        IMorpho _morpho,
        address _swapManager
    ) {
        lendingPool = _lendingPool;
        morpho = _morpho;
        swapManager = _swapManager;
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

    /// @notice Sets the `swapManager`.
    /// @param _swapManager The address of the `swapManager`.
    function setSwapManager(address _swapManager) external override onlyOwner {
        swapManager = _swapManager;
        emit SwapManagerSet(_swapManager);
    }

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _amount The amount of token rewards to claim.
    /// @param _user The address of the user.
    function claimRewards(
        address[] calldata _assets,
        uint256 _amount,
        address _user
    ) external override onlyPositionsManager returns (uint256 amountToClaim) {
        if (_amount == 0) return 0;

        uint256 unclaimedRewards = accrueUserUnclaimedRewards(_assets, _user);
        if (unclaimedRewards == 0) return 0;

        amountToClaim = _amount > unclaimedRewards ? unclaimedRewards : _amount;
        userUnclaimedRewards[_user] = unclaimedRewards - amountToClaim;
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
    ) external override onlyPositionsManager {
        userUnclaimedRewards[_user] += _updateUserAsset(_user, _asset, _userBalance, _totalBalance);
    }

    /// @notice Returns the index of the `_user` for a given `_asset`.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return userIndex_ The index of the user.
    function getUserIndex(address _asset, address _user)
        external
        view
        override
        returns (uint256 userIndex_)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        userIndex_ = localData.userIndex[_user];
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

        for (uint256 i = 0; i < _assets.length; i++) {
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
        }
    }

    /// PUBLIC ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _assets, address _user)
        public
        override
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedRewards[_user];

        for (uint256 i = 0; i < _assets.length; i++) {
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
        }

        userUnclaimedRewards[_user] = unclaimedRewards;
    }

    /// INTERNAL ///

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
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 formerUserIndex = localData.userIndex[_user];
        uint256 newIndex = _getUpdatedIndex(_asset, _totalBalance);

        if (formerUserIndex != newIndex) {
            if (_userBalance != 0)
                accruedRewards = _getRewards(_userBalance, newIndex, formerUserIndex);

            localData.userIndex[_user] = newIndex;
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
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 formerUserIndex = localData.userIndex[_user];
        uint256 newIndex = _getNewIndex(_asset, _totalBalance);

        if (formerUserIndex != newIndex) {
            if (_userBalance != 0)
                accruedRewards = _getRewards(_userBalance, newIndex, formerUserIndex);
        }
    }

    /// @dev Computes and returns the next value of a specific distribution index.
    /// @param _currentIndex The current index of the distribution.
    /// @param _emissionPerSecond The total rewards distributed per second per asset unit, on the distribution.
    /// @param _lastUpdateTimestamp The last moment this distribution was updated.
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return The new index.
    function _getAssetIndex(
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
    /// @return newIndex The new distribution index.
    function _getUpdatedIndex(address _asset, uint256 _totalBalance)
        internal
        virtual
        returns (uint256 newIndex);

    /// @dev Returns the next reward index.
    /// @dev This function is the equivalent of _getUpdatedIndex, but as a view.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _totalBalance The total balance of tokens in the distribution.
    /// @return newIndex The new distribution index.
    function _getNewIndex(address _asset, uint256 _totalBalance)
        internal
        view
        virtual
        returns (uint256 newIndex);
}
