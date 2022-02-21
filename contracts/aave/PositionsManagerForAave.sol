// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/IMatchingEngineForAave.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";
import "./libraries/MatchingEngineFns.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerForAaveStorage.sol";
import "./MatchingEngineForAave.sol";

/// @title PositionsManagerForAave
/// @notice Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
contract PositionsManagerForAave is PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using MatchingEngineFns for IMatchingEngineForAave;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /// Enums ///

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /// Structs ///

    struct AssetLiquidityData {
        uint256 collateralValue; // The collateral value of the asset (in ETH).
        uint256 liquidationValue; // The value which made liquidation possible (in ETH).
        uint256 maxDebtValue; // The maximum possible debt value of the asset (in ETH).
        uint256 debtValue; // The debt value of the asset (in ETH).
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 underlyingPrice; // The price of the token (in ETH).
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
        uint256 ltv; // The LTV applied on this token (in basis point).
    }

    struct LiquidateVars {
        address tokenBorrowedAddress; // The address of the borrowed asset.
        address tokenCollateralAddress; // The address of the collateral asset.
        uint256 debtValue; // The debt value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        uint256 liquidationValue; // The value for a possible liquidation (in ETH).
        uint256 borrowedPrice; // The price of the asset borrowed (in ETH).
        uint256 collateralPrice; // The price of the collateral asset (in ETH).
        uint256 borrowBalance; // Total borrow balance of the user for a given asset (in underlying).
        uint256 supplyBalance; // The total of collateral of the user (in underlying).
        uint256 amountToSeize; // The amount of collateral the liquidator can seize (in underlying).
        uint256 liquidationBonus; // The liquidation bonus on Aave.
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The collateral token unit considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
    }

    struct LiquidityData {
        uint256 collateralValue; // The collateral value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        uint256 debtValue; // The debt value (in ETH).
    }

    /// Events ///

    /// @notice Emitted when a supply happens.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update (in underlying).
    /// @param _balanceInP2P The supply balance in P2P after update (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    event Supplied(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint16 indexed _referralCode
    );

    /// @notice Emitted when a withdrawal happens.
    /// @param _user The address of the withdrawer.
    /// @param _poolTokenAddress The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event Withdrawn(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    event Borrowed(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint16 indexed _referralCode
    );

    /// @notice Emitted when a repay happens.
    /// @param _user The address of the repayer.
    /// @param _poolTokenAddress The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event Repaid(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidatee The address of the liquidatee.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenBorrowedAddress The address of the borrowed asset.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    /// @param _poolTokenCollateralAddress The address of the collateral asset seized.
    event Liquidated(
        address indexed _liquidator,
        address indexed _liquidatee,
        uint256 _amountRepaid,
        address _poolTokenBorrowedAddress,
        uint256 _amountSeized,
        address _poolTokenCollateralAddress
    );

    /// @notice Emitted when the lendingPool is updated on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    /// @param _dataProviderAddress The address of the data provider.
    event AaveContractsUpdated(address _lendingPoolAddress, address _dataProviderAddress);

    /// @dev Emitted when a new value for `NDS` is set.
    /// @param _newValue The new value of `NDS`.
    event NDSSet(uint8 _newValue);

    /// @dev Emitted when a new `maxGas` is set.
    /// @param _maxGas The new `maxGas`.
    event MaxGasSet(MaxGas _maxGas);

    /// @dev Emitted the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address _newTreasuryVaultAddress);

    /// @notice Emitted the address of the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address _newRewardsManagerAddress);

    /// @notice Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address _aaveIncentivesController);

    /// @notice Emitted when a threshold of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the threshold.
    event ThresholdSet(address _marketAddress, uint256 _newValue);

    /// @notice Emitted when the DAO claims fees.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of underlying token claimed.
    event FeesClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address _user, uint256 _amountClaimed);

    /// Errors ///

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// @notice Thrown when only the markets manager can call the function.
    error OnlyMarketsManager();

    /// @notice Thrown when only the markets manager's owner can call the function.
    error OnlyMarketsManagerOwner();

    /// @notice Thrown when the debt value is not above the maximum debt value.
    error DebtValueNotAboveMax();

    /// @notice Thrown when the amount of collateral to seize is above the collateral amount.
    error ToSeizeAboveCollateral();

    /// @notice Thrown when the amount is not above the threshold.
    error AmountNotAboveThreshold();

    /// @notice Thrown when the amount repaid during the liquidation is above what is allowed to be repaid.
    error AmountAboveWhatAllowedToRepay();

    /// Modifiers ///

    /// @notice Prevents a user to access a market not created yet.
    /// @param _poolTokenAddress The address of the market.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        _;
    }

    /// @notice Prevents a user to supply or borrow less than threshold.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amount The amount of token (in underlying).
    modifier isAboveThreshold(address _poolTokenAddress, uint256 _amount) {
        if (_amount < threshold[_poolTokenAddress]) revert AmountNotAboveThreshold();
        _;
    }

    /// @notice Prevents a user to call function only allowed for the `marketsManager`.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManager)) revert OnlyMarketsManager();
        _;
    }

    /// @notice Prevents a user to call function only allowed for `marketsManager`'s owner.
    modifier onlyMarketsManagerOwner() {
        if (msg.sender != marketsManager.owner()) revert OnlyMarketsManagerOwner();
        _;
    }

    /// Constructor ///

    /// @notice Constructs the PositionsManagerForAave contract.
    /// @param _marketsManager The address of the aave `marketsManager`.
    /// @param _lendingPoolAddressesProvider The address of the `addressesProvider`.
    constructor(
        address _marketsManager,
        address _lendingPoolAddressesProvider,
        MaxGas memory _maxGas
    ) {
        maxGas = _maxGas;
        marketsManager = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        matchingEngine = new MatchingEngineForAave();
    }

    /// @notice Updates the `lendingPool` and the `dataProvider`.
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit AaveContractsUpdated(address(lendingPool), address(dataProvider));
    }

    /// @notice Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController)
        external
        onlyMarketsManagerOwner
    {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @dev Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyMarketsManagerOwner {
        NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @dev Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(MaxGas memory _maxGas) external onlyMarketsManagerOwner {
        maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @dev Sets the threshold of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newThreshold The new threshold.
    function setThreshold(address _poolTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_poolTokenAddress] = _newThreshold;
        emit ThresholdSet(_poolTokenAddress, _newThreshold);
    }

    /// @notice Sets the `_newTreasuryVaultAddress`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyMarketsManagerOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyMarketsManagerOwner {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Sets the pause status in case of emergency.
    /// @dev Note: the events are emitted through the Pausable contract.
    function setPauseStatus() external onlyMarketsManagerOwner {
        if (paused()) _unpause();
        else _pause();
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        whenNotPaused
        onlyMarketsManagerOwner
        isMarketCreated(_poolTokenAddress)
    {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    function claimRewards(address[] calldata _assets) external whenNotPaused {
        for (uint256 i; i < _assets.length; i++) {
            (address aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(
                IAToken(_assets[i]).UNDERLYING_ASSET_ADDRESS()
            );
            if (!marketsManager.isCreated(aTokenAddress)) revert MarketNotCreated();
        }

        uint256 amountToClaim = rewardsManager.claimRewards(_assets, type(uint256).max, msg.sender);
        if (amountToClaim > 0) {
            uint256 amountClaimed = aaveIncentivesController.claimRewards(
                _assets,
                amountToClaim,
                msg.sender
            );
            emit RewardsClaimed(msg.sender, amountClaimed);
        }
    }

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        whenNotPaused
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _supply(_poolTokenAddress, _amount, _referralCode, maxGas.supply);
    }

    /// @dev Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _supply(_poolTokenAddress, _amount, _referralCode, _maxGasToConsume);
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        whenNotPaused
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _borrow(_poolTokenAddress, _amount, _referralCode, maxGas.borrow);
    }

    /// @dev Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _borrow(_poolTokenAddress, _amount, _referralCode, _maxGasToConsume);
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        whenNotPaused
    {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            ),
            _amount
        );

        _withdraw(_poolTokenAddress, toWithdraw, msg.sender, msg.sender, maxGas.withdraw);
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant whenNotPaused {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            ),
            _amount
        );

        _repay(_poolTokenAddress, msg.sender, toRepay, maxGas.repay);
    }

    /// @notice Allows someone to liquidate a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying).
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        if (_amount == 0) revert AmountIsZero();

        LiquidateVars memory vars;
        (vars.debtValue, , vars.liquidationValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        if (vars.debtValue <= vars.liquidationValue) revert DebtValueNotAboveMax();

        IAToken poolTokenBorrowed = IAToken(_poolTokenBorrowedAddress);
        vars.tokenBorrowedAddress = poolTokenBorrowed.UNDERLYING_ASSET_ADDRESS();

        vars.borrowBalance = _getUserBorrowBalanceInOf(
            _poolTokenBorrowedAddress,
            _borrower,
            vars.tokenBorrowedAddress
        );

        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Aave. Liquidator cannot repay more than part of the debt (cf close factor on Aave).

        _repay(_poolTokenBorrowedAddress, _borrower, _amount, 0);

        IAToken poolTokenCollateral = IAToken(_poolTokenCollateralAddress);
        vars.tokenCollateralAddress = poolTokenCollateral.UNDERLYING_ASSET_ADDRESS();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        vars.borrowedPrice = oracle.getAssetPrice(vars.tokenBorrowedAddress); // In ETH
        vars.collateralPrice = oracle.getAssetPrice(vars.tokenCollateralAddress); // In ETH

        (vars.collateralReserveDecimals, , , vars.liquidationBonus, , , , , , ) = dataProvider
        .getReserveConfigurationData(vars.tokenCollateralAddress);
        (vars.borrowedReserveDecimals, , , , , , , , , ) = dataProvider.getReserveConfigurationData(
            vars.tokenBorrowedAddress
        );
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        // Calculate the amount of collateral to seize (cf Aave):
        // seizeAmount = repayAmount * liquidationBonus * borrowedPrice * collateralTokenUnit / (collateralPrice * borrowedTokenUnit)
        vars.amountToSeize =
            (_amount * vars.borrowedPrice * vars.collateralTokenUnit * vars.liquidationBonus) /
            (vars.borrowedTokenUnit * vars.collateralPrice * MAX_BASIS_POINTS); // Same mechanism as aave. The collateral amount to seize is given.

        vars.supplyBalance = _getUserSupplyBalanceInOf(
            _poolTokenCollateralAddress,
            _borrower,
            vars.tokenCollateralAddress
        );

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        _withdraw(_poolTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender, 0);
        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            vars.amountToSeize,
            _poolTokenCollateralAddress
        );
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user (in ETH).
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user (in ETH).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum possible debt value of the user (in ETH).
    /// @return liquidationValue The value which made liquidation possible (in ETH).
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue,
            uint256 liquidationValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            collateralValue += assetData.collateralValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            liquidationValue += assetData.liquidationValue;
        }
    }

    /// @notice Returns the maximum amount available for withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        LiquidityData memory data;
        AssetLiquidityData memory assetData;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.maxDebtValue += assetData.maxDebtValue;
        data.debtValue += assetData.debtValue;

        // Not possible to withdraw nor borrow
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = ((data.maxDebtValue - data.debtValue) *
            assetData.tokenUnit) / assetData.underlyingPrice;

        withdrawable =
            (assetData.collateralValue * assetData.tokenUnit) /
            assetData.underlyingPrice;
        if (assetData.ltv != 0) {
            withdrawable = Math.min(
                withdrawable,
                (differenceInUnderlying * MAX_BASIS_POINTS) / assetData.ltv
            );
        }

        borrowable = differenceInUnderlying;
    }

    /// Public ///

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        IPriceOracleGetter oracle
    ) public view returns (AssetLiquidityData memory assetData) {
        // Compute the current debt amount (in underlying)
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        assetData.debtValue = _getUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        // Compute the current collateral amount (in underlying)
        assetData.collateralValue = _getUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH
        (
            uint256 reserveDecimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = dataProvider.getReserveConfigurationData(underlyingAddress);
        assetData.ltv = ltv;
        assetData.liquidationThreshold = liquidationThreshold;
        assetData.tokenUnit = 10**reserveDecimals;

        // Then, convert values to ETH
        assetData.collateralValue =
            (assetData.collateralValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.maxDebtValue = (assetData.collateralValue * ltv) / MAX_BASIS_POINTS;
        assetData.liquidationValue =
            (assetData.collateralValue * liquidationThreshold) /
            MAX_BASIS_POINTS;
        assetData.debtValue =
            (assetData.debtValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// Internal ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) internal {
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManager.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToSupplyToPool = _amount;

        /// Supply in P2P ///

        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchBorrowersDC(
                IAToken(_poolTokenAddress),
                underlyingToken,
                _amount,
                _maxGasToConsume
            ); // In underlying

            if (matched > 0) {
                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    supplyP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            }
            remainingToSupplyToPool -= matched;
        }

        /// Supply on pool ///

        if (remainingToSupplyToPool > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool
            .divWadByRay(normalizedIncome); // Scaled Balance
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyERC20ToPool(_poolTokenAddress, underlyingToken, remainingToSupplyToPool); // Revert on error
        }

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) internal {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        marketsManager.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrowOnPool = _amount;

        /// Borrow in P2P ///

        if (
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchSuppliersDC(
                IAToken(_poolTokenAddress),
                underlyingToken,
                _amount,
                _maxGasToConsume
            ); // In underlying

            if (matched > 0) {
                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    borrowP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            }

            remainingToBorrowOnPool -= matched;
        }

        /// Borrow on pool ///

        if (remainingToBorrowOnPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool
            .divWadByRay(normalizedVariableDebt); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowERC20FromPool(_poolTokenAddress, underlyingToken, remainingToBorrowOnPool);
        }

        underlyingToken.safeTransfer(msg.sender, _amount);
        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Implements withdraw logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasToConsume
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        _checkUserLiquidity(_supplier, _poolTokenAddress, _amount, 0);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
            uint256 withdrawnInUnderlying = Math.min(
                Math.min(onPoolSupplyInUnderlying, remainingToWithdraw),
                poolToken.balanceOf(address(this))
            );

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                withdrawnInUnderlying.divWadByRay(normalizedIncome)
            ); // In poolToken
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
            if (withdrawnInUnderlying > 0)
                _withdrawERC20FromPool(_poolTokenAddress, underlyingToken, withdrawnInUnderlying); // Revert on error
            remainingToWithdraw -= withdrawnInUnderlying;
        }

        /// Transfer withdraw ///

        if (remainingToWithdraw > 0) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.divWadByRay(supplyP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
            uint256 matchedSupply = matchingEngine.matchSuppliersDC(
                poolToken,
                underlyingToken,
                remainingToWithdraw,
                _maxGasToConsume
            );

            /// Hard withdraw ///

            if (remainingToWithdraw > matchedSupply)
                matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    remainingToWithdraw - matchedSupply,
                    _maxGasToConsume
                );
        }

        underlyingToken.safeTransfer(_receiver, _amount);
        emit Withdrawn(
            _supplier,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_receiver].onPool,
            supplyBalanceInOf[_poolTokenAddress][_receiver].inP2P
        );
    }

    /// @notice Implements repay logic.
    /// @dev Note: `msg.sender` must have approved this contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();

        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            address poolTokenAddress = address(poolToken);
            uint256 borrowedOnPool = borrowBalanceInOf[poolTokenAddress][_user].onPool;
            uint256 borrowedOnPoolInUnderlying = borrowedOnPool.mulWadByRay(normalizedVariableDebt);
            uint256 repaidInUnderlying = Math.min(borrowedOnPoolInUnderlying, remainingToRepay);

            borrowBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                repaidInUnderlying.divWadByRay(normalizedVariableDebt)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);
            if (repaidInUnderlying > 0)
                _repayERC20ToPool(
                    _poolTokenAddress,
                    underlyingToken,
                    repaidInUnderlying,
                    normalizedVariableDebt
                ); // Revert on error
            remainingToRepay -= repaidInUnderlying;
        }

        /// Transfer repay ///

        if (remainingToRepay > 0) {
            address poolTokenAddress = address(poolToken);
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);

            borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[poolTokenAddress][_user].inP2P,
                remainingToRepay.divWadByRay(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);
            uint256 matchedBorrow = matchingEngine.matchBorrowersDC(
                poolToken,
                underlyingToken,
                remainingToRepay,
                _maxGasToConsume
            );

            /// Hard repay ///

            if (_amount > matchedBorrow)
                matchingEngine.unmatchSuppliersDC(
                    poolTokenAddress,
                    remainingToRepay - matchedBorrow,
                    _maxGasToConsume
                ); // Revert on error
        }

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    ///@notice Enters the user into the market if not already there.
    ///@param _user The address of the user to update.
    ///@param _poolTokenAddress The address of the market to check.
    function _handleMembership(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }

    /// @notice Checks whether the user can borrow/withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    function _checkUserLiquidity(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
    }

    /// @notice Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum debt value possible of the user (in ETH).
    /// @return liquidationValue The value when liquidation is possible (in ETH).
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    )
        internal
        returns (
            uint256 debtValue,
            uint256 maxDebtValue,
            uint256 liquidationValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            marketsManager.updateP2PExchangeRates(poolTokenEntered);
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            liquidationValue += assetData.liquidationValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += (_borrowedAmount * assetData.underlyingPrice) / assetData.tokenUnit;
                maxDebtValue -= Math.min(
                    maxDebtValue,
                    (_withdrawnAmount * assetData.underlyingPrice * assetData.ltv) /
                        (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
                liquidationValue -= Math.min(
                    liquidationValue,
                    (_withdrawnAmount * assetData.underlyingPrice * assetData.liquidationValue) /
                        (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
            }
        }
    }

    /// @notice Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedIncome(_underlyingTokenAddress)
            );
    }

    /// @notice Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(_underlyingTokenAddress)
            );
    }
}
