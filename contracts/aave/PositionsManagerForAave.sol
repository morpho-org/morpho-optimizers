// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";
import "./logic/P2PLogic.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerForAaveStorage.sol";
import "./MatchingEngineManager.sol";

/// @title PositionsManagerForAave
/// @notice Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
contract PositionsManagerForAave is PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

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
        uint256 maxDebtValue; // The maximum possible debt value of the asset (in ETH).
        uint256 debtValue; // The debt value of the asset (in ETH).
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 underlyingPrice; // The price of the token (in ETH).
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
    }

    struct LiquidityData {
        uint256 collateralValue; // The collateral value (in ETH).
        uint256 maxDebtValue; // The maximum possible debt value (in ETH).
        uint256 debtValue; // The debt value (in ETH).
    }

    // Struct to avoid stack too deep error
    struct LiquidateVars {
        uint256 debtValue; // The debt value (in ETH).
        uint256 maxDebtValue; // The maximum possible debt value (in ETH).
        uint256 borrowBalance; // Total borrow balance of the user for a given asset (in underlying).
        uint256 amountToSeize; // The amount of collateral the liquidator can seize (in underlying).
        uint256 borrowedPrice; // The price of the asset borrowed (in ETH).
        uint256 collateralPrice; // The price of the collateral asset (in ETH).
        uint256 normalizedIncome; // The normalized income of the asset.
        uint256 totalCollateral; // The total of collateral of the user (in underlying).
        uint256 liquidationBonus; // The liquidation bonus on Aave (in basis point).
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The collateral token unit considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The borrowed token unit considering its decimals.
        address tokenBorrowedAddress; // The address of the borrowed asset.
        address tokenCollateralAddress; // The address of the collateral asset.
        IPriceOracleGetter oracle; // The Aave oracle.
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

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the `lendingPool` is updated on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolUpdated(address _lendingPoolAddress);

    /// @notice Emitted the maximum number of users to have in the tree is updated.
    /// @param _newValue The new value of the maximum number of users to have in the tree.
    event MaxNumberSet(uint16 _newValue);

    /// @notice Emitted the address of the `treasuryVault` is set.
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

    /// @notice Emitted when a cap value of a market is set.
    /// @param _poolTokenAddress The address of the market to set.
    /// @param _newValue The new value of the cap.
    event CapValueSet(address _poolTokenAddress, uint256 _newValue);

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

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// @notice Thrown when only the markets manager can call the function.
    error OnlyMarketsManager();

    /// @notice Thrown when only the markets manager's owner can call the function.
    error OnlyMarketsManagerOwner();

    /// @notice Thrown when the supply is above the cap value.
    error SupplyAboveCapValue();

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
        if (!marketsManagerForAave.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        _;
    }

    /// @notice Prevents a user to supply or borrow less than threshold.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amount The amount of token (in underlying).
    modifier isAboveThreshold(address _poolTokenAddress, uint256 _amount) {
        if (_amount < threshold[_poolTokenAddress]) revert AmountNotAboveThreshold();
        _;
    }

    /// @notice Prevents a user to call function only allowed for the `marketsManagerForAave`.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManagerForAave)) revert OnlyMarketsManager();
        _;
    }

    /// @notice Prevents a user to call function only allowed for `marketsManagerForAave`'s owner.
    modifier onlyMarketsManagerOwner() {
        if (msg.sender != marketsManagerForAave.owner()) revert OnlyMarketsManagerOwner();
        _;
    }

    /// Constructor ///

    /// @notice Constructs the PositionsManagerForAave contract.
    /// @param _marketsManager The address of the aave `marketsManager`.
    /// @param _lendingPoolAddressesProvider The address of the `addressesProvider`.
    constructor(address _marketsManager, address _lendingPoolAddressesProvider) {
        marketsManagerForAave = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        matchingEngineManager = new MatchingEngineManager();
    }

    /// @notice Updates the `lendingPool` and the `dataProvider`.
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
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

    /// @notice Sets the maximum number of users in data structure.
    /// @param _newMaxNumber The maximum number of users to sort in the data structure.
    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external onlyMarketsManagerOwner {
        NMAX = _newMaxNumber;
        emit MaxNumberSet(_newMaxNumber);
    }

    /// @notice Sets the threshold of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newThreshold The new threshold.
    function setThreshold(address _poolTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_poolTokenAddress] = _newThreshold;
        emit ThresholdSet(_poolTokenAddress, _newThreshold);
    }

    /// @notice Sets the max cap of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newCapValue The new threshold.
    function setCapValue(address _poolTokenAddress, uint256 _newCapValue)
        external
        onlyMarketsManager
    {
        capValue[_poolTokenAddress] = _newCapValue;
        emit CapValueSet(_poolTokenAddress, _newCapValue);
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

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        onlyMarketsManagerOwner
        isMarketCreated(_poolTokenAddress)
    {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.transfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    function claimRewards(address[] calldata _assets) external {
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
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        if (capValue[_poolTokenAddress] != type(uint256).max)
            _checkCapValue(_poolTokenAddress, underlyingToken, msg.sender, _amount);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        DataStructs.CommonParams memory params = DataStructs.CommonParams({
            amount: _amount,
            poolTokenAddress: _poolTokenAddress,
            underlyingToken: underlyingToken,
            lendingPool: lendingPool,
            marketsManagerForAave: marketsManagerForAave,
            matchingEngineManager: matchingEngineManager
        });

        /* If some borrowers are waiting on Aave, Morpho matches the supplier in P2P with them as much as possible */
        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            params.amount -= P2PLogic.supplyPositionToP2P(
                params,
                msg.sender,
                NMAX,
                dataProvider,
                borrowersOnPool,
                supplyBalanceInOf,
                borrowBalanceInOf
            );

        /* If there aren't enough borrowers waiting on Aave to match all the tokens supplied, the rest is supplied to Aave */
        if (params.amount > 0)
            PoolLogic.supplyPositionToPool(
                params,
                msg.sender,
                lendingPool,
                matchingEngineManager,
                supplyBalanceInOf
            );

        emit Supplied(
            msg.sender,
            params.poolTokenAddress,
            params.amount,
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
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        DataStructs.CommonParams memory params = DataStructs.CommonParams({
            amount: _amount,
            poolTokenAddress: _poolTokenAddress,
            underlyingToken: underlyingToken,
            lendingPool: lendingPool,
            marketsManagerForAave: marketsManagerForAave,
            matchingEngineManager: matchingEngineManager
        });

        /* If some suppliers are waiting on Aave, Morpho matches the borrower in P2P with them as much as possible */
        if (
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            params.amount -= P2PLogic.borrowPositionFromP2P(
                params,
                msg.sender,
                NMAX,
                suppliersOnPool,
                supplyBalanceInOf,
                borrowBalanceInOf
            );

        /* If there aren't enough suppliers waiting on Aave to match all the tokens borrowed, the rest is borrowed from Aave */
        if (params.amount > 0)
            PoolLogic.borrowPositionFromPool(
                params,
                msg.sender,
                lendingPool,
                matchingEngineManager,
                borrowBalanceInOf
            );

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

    /// @notice Withdraws underlying tokens in a specific market.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole balance is withdrawn.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Withdraw all
        if (_amount == type(uint256).max) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(poolToken.UNDERLYING_ASSET_ADDRESS())
            );
            uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
                _poolTokenAddress
            );

            _amount =
                supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool.mulWadByRay(
                    normalizedIncome
                ) +
                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P.mulWadByRay(
                    supplyP2PExchangeRate
                );
        }

        _withdraw(_poolTokenAddress, _amount, msg.sender, msg.sender);
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole debt is repaid.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Repay all
        if (_amount == type(uint256).max) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                poolToken.UNDERLYING_ASSET_ADDRESS()
            );
            uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
                _poolTokenAddress
            );

            _amount =
                borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool.mulWadByRay(
                    normalizedVariableDebt
                ) +
                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P.mulWadByRay(
                    borrowP2PExchangeRate
                );
        }

        _repay(_poolTokenAddress, msg.sender, _amount);
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
        (vars.debtValue, vars.maxDebtValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        if (vars.debtValue <= vars.maxDebtValue) revert DebtValueNotAboveMax();

        IAToken poolTokenBorrowed = IAToken(_poolTokenBorrowedAddress);
        IAToken poolTokenCollateral = IAToken(_poolTokenCollateralAddress);
        vars.tokenBorrowedAddress = poolTokenBorrowed.UNDERLYING_ASSET_ADDRESS();
        vars.tokenCollateralAddress = poolTokenCollateral.UNDERLYING_ASSET_ADDRESS();
        vars.borrowBalance =
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(vars.tokenBorrowedAddress)
            ) +
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].inP2P.mulWadByRay(
                marketsManagerForAave.borrowP2PExchangeRate(_poolTokenBorrowedAddress)
            );
        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Aave. Liquidator cannot repay more than part of the debt (cf close factor on Aave).

        vars.oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        _repay(_poolTokenBorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.collateralPrice = vars.oracle.getAssetPrice(vars.tokenCollateralAddress); // In ETH
        vars.borrowedPrice = vars.oracle.getAssetPrice(vars.tokenBorrowedAddress); // In ETH
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
        vars.normalizedIncome = lendingPool.getReserveNormalizedIncome(vars.tokenCollateralAddress);
        vars.totalCollateral =
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].onPool.mulWadByRay(
                vars.normalizedIncome
            ) +
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].inP2P.mulWadByRay(
                marketsManagerForAave.supplyP2PExchangeRate(_poolTokenCollateralAddress)
            );

        if (vars.amountToSeize > vars.totalCollateral) revert ToSeizeAboveCollateral();

        _withdraw(_poolTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender);

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
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
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

        withdrawable = Math.min(
            (differenceInUnderlying * MAX_BASIS_POINTS) / assetData.liquidationThreshold,
            (assetData.collateralValue * assetData.tokenUnit) / assetData.underlyingPrice
        );
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
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            _poolTokenAddress
        );
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            _poolTokenAddress
        );

        // First, compute the values in underlying
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(underlyingAddress);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            underlyingAddress
        );

        assetData.debtValue =
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(normalizedVariableDebt) +
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(borrowP2PExchangeRate);

        assetData.collateralValue =
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(normalizedIncome) +
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(supplyP2PExchangeRate);

        assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH
        (uint256 reserveDecimals, , uint256 liquidationThreshold, , , , , , , ) = dataProvider
        .getReserveConfigurationData(underlyingAddress);
        assetData.liquidationThreshold = liquidationThreshold;
        assetData.tokenUnit = 10**reserveDecimals;

        // Then, convert values to ETH
        assetData.collateralValue =
            (assetData.collateralValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.maxDebtValue =
            (assetData.collateralValue * liquidationThreshold) /
            MAX_BASIS_POINTS;
        assetData.debtValue =
            (assetData.debtValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// Internal ///

    /// @notice Implements withdraw logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        _checkUserLiquidity(_supplier, _poolTokenAddress, _amount, 0);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        DataStructs.CommonParams memory params = DataStructs.CommonParams({
            amount: _amount,
            poolTokenAddress: _poolTokenAddress,
            underlyingToken: underlyingToken,
            lendingPool: lendingPool,
            marketsManagerForAave: marketsManagerForAave,
            matchingEngineManager: matchingEngineManager
        });

        /* If user has some tokens waiting on Aave */
        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0)
            params.amount -= PoolLogic.withdrawPositionFromPool(
                params,
                _supplier,
                lendingPool,
                matchingEngineManager,
                supplyBalanceInOf
            );

        /* If there remains some tokens to withdraw, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (params.amount > 0)
            P2PLogic.withdrawPositionFromP2P(
                params,
                _supplier,
                NMAX,
                suppliersOnPool,
                borrowersInP2P,
                supplyBalanceInOf,
                borrowBalanceInOf
            );

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
    /// @notice `msg.sender` must have approved this contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();

        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        DataStructs.CommonParams memory params = DataStructs.CommonParams({
            amount: _amount,
            poolTokenAddress: _poolTokenAddress,
            underlyingToken: underlyingToken,
            lendingPool: lendingPool,
            marketsManagerForAave: marketsManagerForAave,
            matchingEngineManager: matchingEngineManager
        });

        /* If user is borrowing tokens on Aave */
        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0)
            params.amount -= PoolLogic.repayPositionToPool(
                params,
                _user,
                lendingPool,
                dataProvider,
                matchingEngineManager,
                borrowBalanceInOf
            );

        /* If there remains some tokens to repay, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (params.amount > 0)
            P2PLogic.repayPositionToP2P(
                params,
                _user,
                NMAX,
                dataProvider,
                borrowersOnPool,
                suppliersInP2P,
                supplyBalanceInOf,
                borrowBalanceInOf
            );

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    /// @notice Checks that the total supply of `supplier` is below the cap on a specific market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @param _underlyingToken The underlying token of the market.
    /// @param _supplier The address of the _supplier to check.
    /// @param _amount The amount to add to the current supply.
    function _checkCapValue(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal view {
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            _poolTokenAddress
        );
        uint256 totalSuppliedInUnderlying = supplyBalanceInOf[_poolTokenAddress][_supplier]
        .inP2P
        .mulWadByRay(supplyP2PExchangeRate) +
            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool.mulWadByRay(normalizedIncome);
        if (totalSuppliedInUnderlying + _amount > capValue[_poolTokenAddress])
            revert SupplyAboveCapValue();
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
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
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
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256 debtValue, uint256 maxDebtValue) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            marketsManagerForAave.updateRates(poolTokenEntered);
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += (_borrowedAmount * assetData.underlyingPrice) / assetData.tokenUnit;
                maxDebtValue -= Math.min(
                    maxDebtValue,
                    (_withdrawnAmount *
                        assetData.underlyingPrice *
                        assetData.liquidationThreshold) / (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
            }
        }
    }
}
