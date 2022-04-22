// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/LibPositionsManagerGetters.sol";
import "../libraries/LibStorage.sol";

import "./PositionsManagerGetters.sol";

contract PositionsManagerGovernor is PositionsManagerGetters {
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

    /// @notice Thrown when only the markets manager can call the function.
    error OnlyMarketsManager();

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// @notice Thrown when the address is the zero address.
    error ZeroAddress();

    /// UPGRADE ///

    /// @notice Initializes the PositionsManager contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _comptroller The `comptroller`.
    /// @param _maxGas The `maxGas`.
    /// @param _NDS The `NDS`.
    /// @param _cEth The cETH address.
    /// @param _weth The wETH address.
    function initialize(
        IMarketsManager _marketsManager,
        IComptroller _comptroller,
        Types.MaxGas memory _maxGas,
        uint8 _NDS,
        address _cEth,
        address _weth
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        PositionsStorage storage p = ps();

        p.marketsManager = _marketsManager;
        p.comptroller = _comptroller;

        p.maxGas = _maxGas;
        p.NDS = _NDS;

        p.cEth = _cEth;
        p.wEth = _weth;
    }

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
        ps().rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !ps().isCompRewardsActive;
        ps().isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// @notice Creates markets.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @return The results of entered.
    function createMarket(address _poolTokenAddress) external returns (uint256[] memory) {
        PositionsStorage storage p = ps();
        if (msg.sender != address(p.marketsManager)) revert OnlyMarketsManager();
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        return p.comptroller.enterMarkets(marketToEnter);
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress) external onlyOwner {
        PositionsStorage storage p = ps();
        if (!p.marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        if (p.marketsManager.paused(_poolTokenAddress)) revert MarketPaused();
        if (p.treasuryVault == address(0)) revert ZeroAddress();

        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));

        if (amountToClaim == 0) revert AmountIsZero();

        underlyingToken.safeTransfer(p.treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }
}
