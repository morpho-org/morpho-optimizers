// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IGetterUnderlyingAsset.sol";
import "./interfaces/IRewardsManagerForAave.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RewardsManagerForAave is IRewardsManagerForAave, Ownable {
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
    IPositionsManagerForAave public immutable positionsManager;
    ILendingPool public immutable lendingPool;
    address public override swapManager;

    /// EVENTS ///

    /// @notice Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address indexed _aaveIncentivesController);

    /// @notice Emitted the address of the `swapManager` is set.
    /// @param _swapManager The new address of the `swapManager`.
    event SwapManagerSet(address indexed _swapManager);

    /// @notice Emitted when the user's index is updated.
    /// @param _user The address of the user whose index has been updated.
    /// @param _poolTokenAddress The address of the market from where the index is updated.
    /// @param _index The new index value.
    event UserIndexUpdated(address _user, address _poolTokenAddress, uint256 _index);

    /// ERRORS ///

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when an invalid asset is passed to accrue rewards.
    error InvalidAsset();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the positions manager only.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _lendingPool The `lendingPool`.
    /// @param _positionsManager The `positionsManager`.
    /// @param _swapManager The address of the `swapManager`.
    constructor(
        ILendingPool _lendingPool,
        IPositionsManagerForAave _positionsManager,
        address _swapManager
    ) {
        lendingPool = _lendingPool;
        positionsManager = _positionsManager;
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
    function setSwapManager(address _swapManager) external onlyOwner {
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
    /// @param _stakedByUser The amount of tokens staked by the user in the distribution at the moment.
    /// @param _totalStaked The total of tokens staked in the distribution.
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) external override onlyPositionsManager {
        userUnclaimedRewards[_user] += _updateUserAsset(_user, _asset, _stakedByUser, _totalStaked);
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
            uint256 stakedByUser;
            if (asset == reserve.aTokenAddress)
                stakedByUser = positionsManager
                .supplyBalanceInOf(reserve.aTokenAddress, _user)
                .onPool;
            else if (asset == reserve.variableDebtTokenAddress)
                stakedByUser = positionsManager
                .borrowBalanceInOf(reserve.aTokenAddress, _user)
                .onPool;
            else revert InvalidAsset();

            uint256 totalStaked = IScaledBalanceToken(asset).scaledTotalSupply();

            unclaimedRewards += _updateUserAsset(_user, asset, stakedByUser, totalStaked);
        }

        userUnclaimedRewards[_user] = unclaimedRewards;
    }

    /// INTERNAL ///

    /// @dev Updates the state of an user in a distribution.
    /// @param _user The address of the user.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _stakedByUser The amount of tokens staked by the user in the distribution at the moment.
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return accruedRewards The accrued rewards for the user until the moment for this asset.
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

            emit UserIndexUpdated(_user, _asset, newIndex);
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
        uint256 _lastUpdateTimestamp,
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

    /// @dev Returns the next reward index.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _totalStaked The total of tokens staked in the distribution.
    /// @return newIndex The new distribution index.
    function _getUpdatedIndex(address _asset, uint256 _totalStaked)
        internal
        virtual
        returns (uint256 newIndex);
}
