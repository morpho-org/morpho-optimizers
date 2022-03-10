// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import "./interfaces/IMatchingEngineForAave.sol";

import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/MatchingEngineFns.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerForAaveStorage.sol";
import "./MatchingEngineForAave.sol";

/// @title PositionsManagerForAave
/// @notice Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
contract PositionsManagerForAave is PositionsManagerForAaveStorage {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using MatchingEngineFns for IMatchingEngineForAave;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

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

    /// @notice Emitted when a market is paused or unpaused.
    /// @param _poolTokenAddress The address of the pool token concerned..
    /// @param _newStatus The new pause status of the market.
    event PauseStatusSet(address _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when the DAO claims fees.
    /// @param _poolTokenAddress The address of the pool token concerned.
    /// @param _amountClaimed The amount of underlying token claimed.
    event FeesClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the pool token concerned.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @notice Emitted when a user claims rewards.
    /// @param _user The address of the claimer.
    /// @param _amountClaimed The amount of reward token claimed.
    event RewardsClaimed(address _user, uint256 _amountClaimed);

    /// @dev Emitted when a user claims rewards and swaps them to Morpho tokens.
    /// @param _user The address of the claimer.
    /// @param _amountIn The amount of reward token swapped.
    /// @param _amountOut The amount of tokens received.
    event RewardsClaimedAndSwapped(address _user, uint256 _amountIn, uint256 _amountOut);

    /// Errors ///

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// @notice Thrown when the market is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// @notice Thrown when the debt value is not above the maximum debt value.
    error DebtValueNotAboveMax();

    /// @notice Thrown when the amount of collateral to seize is above the collateral amount.
    error ToSeizeAboveCollateral();

    /// @notice Thrown when the amount repaid during the liquidation is above what is allowed to be repaid.
    error AmountAboveWhatAllowedToRepay();

    /// Modifiers ///

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPaused(address _poolTokenAddress) {
        if (!marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        if (paused[_poolTokenAddress]) revert MarketPaused();
        _;
    }

    /// External ///

    /// @notice Initializes the PositionsManagerForAave contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _lendingPoolAddressesProvider The `addressesProvider`.
    /// @param _swapManager The `swapManager`.
    function initialize(
        IMarketsManagerForAave _marketsManager,
        IPoolAddressesProvider _lendingPoolAddressesProvider,
        ISwapManager _swapManager,
        MaxGas memory _maxGas
    ) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();

        maxGas = _maxGas;
        marketsManager = _marketsManager;
        addressesProvider = _lendingPoolAddressesProvider;
        pool = IPool(addressesProvider.getPool());
        matchingEngine = new MatchingEngineForAave();
        swapManager = _swapManager;

        NDS = 20;
    }

    /// @notice Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController) external onlyOwner {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @dev Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyOwner {
        NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @dev Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(MaxGas memory _maxGas) external onlyOwner {
        maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @notice Sets the `_newTreasuryVaultAddress`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @dev Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyOwner {
        rewardsManager = IRewardsManagerForAave(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @dev Sets the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function setPauseStatus(address _poolTokenAddress) external onlyOwner {
        bool newPauseStatus = !paused[_poolTokenAddress];
        paused[_poolTokenAddress] = newPauseStatus;
        emit PauseStatusSet(_poolTokenAddress, newPauseStatus);
    }

    /// @dev Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        onlyOwner
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _swap Whether or not to swap reward tokens for Morpho tokens.
    function claimRewards(address[] calldata _assets, bool _swap) external {
        uint256 amountToClaim = rewardsManager.claimRewards(_assets, type(uint256).max, msg.sender);

        if (amountToClaim > 0) {
            if (_swap) {
                uint256 amountClaimed = aaveIncentivesController.claimRewards(
                    _assets,
                    amountToClaim,
                    address(swapManager)
                );
                uint256 amountOut = swapManager.swapToMorphoToken(amountClaimed, msg.sender);
                emit RewardsClaimedAndSwapped(msg.sender, amountClaimed, amountOut);
            } else {
                uint256 amountClaimed = aaveIncentivesController.claimRewards(
                    _assets,
                    amountToClaim,
                    msg.sender
                );
                emit RewardsClaimed(msg.sender, amountClaimed);
            }
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
    ) external nonReentrant {
        _supply(_poolTokenAddress, _amount, maxGas.supply);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        _supply(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external nonReentrant {
        _borrow(_poolTokenAddress, _amount, maxGas.borrow);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        _borrow(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
            ),
            _amount
        );

        _checkUserLiquidity(msg.sender, _poolTokenAddress, toWithdraw, 0);
        _withdraw(_poolTokenAddress, toWithdraw, msg.sender, msg.sender, maxGas.withdraw);
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
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
    ) external nonReentrant {
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

        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = pool
        .getConfiguration(vars.tokenCollateralAddress)
        .getParams();
        (, , , vars.borrowedReserveDecimals, , ) = pool
        .getConfiguration(vars.tokenBorrowedAddress)
        .getParams();
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

        DataTypes.ReserveData memory reserve = pool.getReserveData(underlyingAddress);
        bool isUsingAsCollateral = pool.getUserConfiguration(address(this)).isUsingAsCollateral(
            reserve.id
        );

        // Compute the current collateral amount (in underlying)
        if (isUsingAsCollateral)
            assetData.collateralValue = _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                _user,
                underlyingAddress
            );

        assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH
        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, , ) = pool
        .getConfiguration(underlyingAddress)
        .getParams();
        assetData.ltv = ltv;
        assetData.liquidationThreshold = liquidationThreshold;
        assetData.tokenUnit = 10**reserveDecimals;

        // Then, convert values to base currency
        if (isUsingAsCollateral) {
            assetData.collateralValue =
                (assetData.collateralValue * assetData.underlyingPrice) /
                assetData.tokenUnit;
            assetData.maxDebtValue = (assetData.collateralValue * ltv) / MAX_BASIS_POINTS;
            assetData.liquidationValue =
                (assetData.collateralValue * liquidationThreshold) /
                MAX_BASIS_POINTS;
        }
        assetData.debtValue =
            (assetData.debtValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// Internal ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManager.updateRates(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
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
                _repayERC20ToPool(
                    _poolTokenAddress,
                    underlyingToken,
                    matched,
                    pool.getReserveNormalizedVariableDebt(address(underlyingToken))
                ); // Revert on error

                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    supplyP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            }
            remainingToSupplyToPool -= matched;
        }

        /// Supply on pool ///

        if (remainingToSupplyToPool > 0) {
            uint256 normalizedIncome = pool.getReserveNormalizedIncome(address(underlyingToken));
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool
            .divWadByRay(normalizedIncome); // Scaled Balance
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyERC20ToPool(_poolTokenAddress, underlyingToken, remainingToSupplyToPool); // Revert on error
        }
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
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
                matched = Math.min(matched, IAToken(_poolTokenAddress).balanceOf(address(this)));
                _withdrawERC20FromPool(_poolTokenAddress, underlyingToken, matched); // Revert on error

                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    borrowP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            }

            remainingToBorrowOnPool -= matched;
        }

        /// Borrow on pool ///

        if (remainingToBorrowOnPool > 0) {
            uint256 normalizedVariableDebt = pool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool
            .divWadByRay(normalizedVariableDebt); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowERC20FromPool(_poolTokenAddress, underlyingToken, remainingToBorrowOnPool);
        }

        underlyingToken.safeTransfer(msg.sender, _amount);
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
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 normalizedIncome = pool.getReserveNormalizedIncome(address(underlyingToken));
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 withdrawnInUnderlying = Math.min(
                Math.min(onPoolSupply.mulWadByRay(normalizedIncome), remainingToWithdraw),
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
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.divWadByRay(
                    marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
                )
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            uint256 matched;
            if (
                suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchSuppliersDC(
                    poolToken,
                    underlyingToken,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    matched = Math.min(
                        matched,
                        IAToken(_poolTokenAddress).balanceOf(address(this))
                    );
                    _withdrawERC20FromPool(_poolTokenAddress, underlyingToken, matched); // Revert on error
                }
            }

            /// Hard withdraw ///

            if (remainingToWithdraw > matched) {
                uint256 toUnmatch = remainingToWithdraw - matched;
                matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    toUnmatch,
                    _maxGasToConsume / 2
                );

                _borrowERC20FromPool(_poolTokenAddress, underlyingToken, toUnmatch); // Revert on error
            }
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

    /// @dev Implements repay logic.
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
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();

        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 normalizedVariableDebt = pool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            uint256 repaidInUnderlying = Math.min(
                borrowedOnPool.mulWadByRay(normalizedVariableDebt),
                remainingToRepay
            );

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                repaidInUnderlying.divWadByRay(normalizedVariableDebt)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

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
            uint256 matched;

            borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[poolTokenAddress][_user].inP2P,
                remainingToRepay.divWadByRay(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);

            if (
                borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchBorrowersDC(
                    poolToken,
                    underlyingToken,
                    remainingToRepay,
                    _maxGasToConsume / 2
                );

                _repayERC20ToPool(
                    poolTokenAddress,
                    underlyingToken,
                    matched,
                    pool.getReserveNormalizedVariableDebt(address(underlyingToken))
                ); // Revert on error
            }

            /// Hard repay ///

            if (_amount > matched) {
                uint256 toSupply = matchingEngine.unmatchSuppliersDC(
                    poolTokenAddress,
                    remainingToRepay - matched,
                    _maxGasToConsume / 2
                ); // Revert on error

                if (toSupply > 0) _supplyERC20ToPool(_poolTokenAddress, underlyingToken, toSupply); // Revert on error
            }
        }

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    ///@dev Enters the user into the market if not already there.
    ///@param _user The address of the user to update.
    ///@param _poolTokenAddress The address of the market to check.
    function _handleMembership(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }

    /// @dev Checks whether the user can borrow/withdraw or not.
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

    /// @dev Returns the debt value, max debt value of a given user.
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

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
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
                pool.getReserveNormalizedIncome(_underlyingTokenAddress)
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
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
                pool.getReserveNormalizedVariableDebt(_underlyingTokenAddress)
            );
    }

    /// @dev Supplies undelrying tokens to Aave.
    /// @param _poolTokenAddress The address of the market
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        _underlyingToken.safeApprove(address(pool), _amount);
        pool.supply(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(
            address(_underlyingToken)
        );
        (uint256 ltv, , , , , ) = configuration.getParams();
        uint256 debtCeiling = configuration.getDebtCeiling();
        // TODO: improve this.
        if (ltv == 0 || debtCeiling != 0)
            pool.setUserUseReserveAsCollateral(address(_underlyingToken), false);
        else pool.setUserUseReserveAsCollateral(address(_underlyingToken), true);
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        pool.withdraw(address(_underlyingToken), _amount, address(this));
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        pool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) internal {
        _underlyingToken.safeApprove(address(pool), _amount);
        IVariableDebtToken variableDebtToken = IVariableDebtToken(
            pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            variableDebtToken.scaledBalanceOf(address(this)).mulWadByRay(_normalizedVariableDebt)
        );
        pool.repay(address(_underlyingToken), _amount, VARIABLE_INTEREST_MODE, address(this));
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @dev Overrides `_authorizeUpgrade` OZ function with onlyOwner Access Control.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
