// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerForAaveStorage.sol";
import "./MatchingEngineManager.sol";

/// @title PositionsManagerForAave
/// @dev Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
contract PositionsManagerForAave is PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
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
        uint256 maxDebtValue; // The maximum possible debt value of the asset (in ETH).
        uint256 debtValue; // The debt value of the asset (in ETH).
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 underlyingPrice; // The price of the token (in ETH).
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
    }

    struct LiquidateVars {
        uint256 debtValue; // The debt value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        address tokenBorrowedAddress; // The address of the borrowed asset.
        address tokenCollateralAddress; // The address of the collateral asset.
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

    /// @dev Emitted when a supply happens.
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

    /// @dev Emitted when a withdrawal happens.
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

    /// @dev Emitted when a borrow happens.
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

    /// @dev Emitted when a repay happens.
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

    /// @dev Emitted when a liquidation happens.
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

    /// @dev Emitted when the position of a supplier is updated.
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

    /// @dev Emitted when the position of a borrower is updated.
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

    /// @dev Emitted when the `lendingPool` is updated on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolUpdated(address _lendingPoolAddress);

    /// @dev Emitted the maximum number of users to have in the tree is updated.
    /// @param _newValue The new value of the maximum number of users to have in the tree.
    event MaxNumberSet(uint16 _newValue);

    /// @dev Emitted the address of the `treasuryVault` is set.
    /// @param _newTreasuryVaultAddress The new address of the `treasuryVault`.
    event TreasuryVaultSet(address _newTreasuryVaultAddress);

    /// @dev Emitted the address of the `rewardsManager` is set.
    /// @param _newRewardsManagerAddress The new address of the `rewardsManager`.
    event RewardsManagerSet(address _newRewardsManagerAddress);

    /// @dev Emitted the address of the `aaveIncentivesController` is set.
    /// @param _aaveIncentivesController The new address of the `aaveIncentivesController`.
    event AaveIncentivesControllerSet(address _aaveIncentivesController);

    /// @dev Emitted when a threshold of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the threshold.
    event ThresholdSet(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a cap value of a market is set.
    /// @param _poolTokenAddress The address of the market to set.
    /// @param _newValue The new value of the cap.
    event CapValueSet(address _poolTokenAddress, uint256 _newValue);

    /// @dev Emitted when the DAO claims fees.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of underlying token claimed.
    event FeesClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @dev Emitted when a reserve fee is claimed.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amountClaimed The amount of reward token claimed.
    event ReserveFeeClaimed(address _poolTokenAddress, uint256 _amountClaimed);

    /// @dev Emitted when a user claims rewards.
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

    /// @dev Prevents a user to access a market not created yet.
    /// @param _poolTokenAddress The address of the market.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!marketsManagerForAave.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        _;
    }

    /// @dev Prevents a user to supply or borrow less than threshold.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amount The amount of token (in underlying).
    modifier isAboveThreshold(address _poolTokenAddress, uint256 _amount) {
        if (_amount < threshold[_poolTokenAddress]) revert AmountNotAboveThreshold();
        _;
    }

    /// @dev Prevents a user to call function only allowed for the `marketsManagerForAave`.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManagerForAave)) revert OnlyMarketsManager();
        _;
    }

    /// @dev Prevents a user to call function only allowed for `marketsManagerForAave`'s owner.
    modifier onlyMarketsManagerOwner() {
        if (msg.sender != marketsManagerForAave.owner()) revert OnlyMarketsManagerOwner();
        _;
    }

    /// Constructor ///

    /// @dev Constructs the PositionsManagerForAave contract.
    /// @param _marketsManager The address of the aave `marketsManager`.
    /// @param _lendingPoolAddressesProvider The address of the `addressesProvider`.
    constructor(address _marketsManager, address _lendingPoolAddressesProvider) {
        marketsManagerForAave = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        matchingEngineManager = new MatchingEngineManager();
    }

    /// @dev Updates the `lendingPool` and the `dataProvider`.
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
    }

    /// @dev Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController)
        external
        onlyMarketsManagerOwner
    {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @dev Sets the maximum number of users in data structure.
    /// @param _newMaxNumber The maximum number of users to sort in the data structure.
    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external onlyMarketsManagerOwner {
        NMAX = _newMaxNumber;
        emit MaxNumberSet(_newMaxNumber);
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

    /// @dev Sets the max cap of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newCapValue The new threshold.
    function setCapValue(address _poolTokenAddress, uint256 _newCapValue)
        external
        onlyMarketsManager
    {
        capValue[_poolTokenAddress] = _newCapValue;
        emit CapValueSet(_poolTokenAddress, _newCapValue);
    }

    /// @dev Sets the `_newTreasuryVaultAddress`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyMarketsManagerOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @dev Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyMarketsManagerOwner {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @dev Transfers the protocol reserve fee to the DAO.
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

    /// @dev Claims rewards for the given assets and the unclaimed rewards.
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

    /// @dev Gets the head of the data structure on a specific market (for UI).
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

    /// @dev Gets the next user after `_user` in the data structure on a specific market (for UI).
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

    /// @dev Supplies underlying tokens in a specific market.
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
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Aave, Morpho matches the supplier in P2P with them as much as possible */
        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            remainingToSupplyToPool -= _supplyPositionToP2P(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough borrowers waiting on Aave to match all the tokens supplied, the rest is supplied to Aave */
        if (remainingToSupplyToPool > 0)
            _supplyPositionToPool(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                remainingToSupplyToPool
            );

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Borrows underlying tokens in a specific market.
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
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Aave, Morpho matches the borrower in P2P with them as much as possible */
        if (
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManagerForAave.noP2P(_poolTokenAddress)
        )
            remainingToBorrowOnPool -= _borrowPositionFromP2P(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough suppliers waiting on Aave to match all the tokens borrowed, the rest is borrowed from Aave */
        if (remainingToBorrowOnPool > 0)
            _borrowPositionFromPool(
                IAToken(_poolTokenAddress),
                underlyingToken,
                msg.sender,
                remainingToBorrowOnPool
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

    /// @dev Withdraws underlying tokens in a specific market.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole balance is withdrawn.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Withdraw all
        if (_amount == type(uint256).max) {
            _amount = _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            );
        }

        _withdraw(_poolTokenAddress, _amount, msg.sender, msg.sender);
    }

    /// @dev Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @dev Note: If `_amount` is equal to the uint256's maximum value, the whole debt is repaid.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManagerForAave.updateRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        // Repay all
        if (_amount == type(uint256).max) {
            _amount = _getUserBorrowBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            );
        }

        _repay(_poolTokenAddress, msg.sender, _amount);
    }

    /// @dev Allows someone to liquidate a position.
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
        vars.tokenBorrowedAddress = poolTokenBorrowed.UNDERLYING_ASSET_ADDRESS();

        vars.borrowBalance = _getUserBorrowBalanceInOf(
            _poolTokenBorrowedAddress,
            _borrower,
            vars.tokenBorrowedAddress
        );

        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Aave. Liquidator cannot repay more than part of the debt (cf close factor on Aave).

        _repay(_poolTokenBorrowedAddress, _borrower, _amount);

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

    /// @dev Returns the collateral value, debt value and max debt value of a given user (in ETH).
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

    /// @dev Returns the maximum amount available for withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
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

    /// @dev Returns the data related to `_poolTokenAddress` for the `_user`.
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

    /// @dev Implements withdraw logic.
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
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Aave */
        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0)
            remainingToWithdraw -= _withdrawPositionFromPool(
                poolToken,
                underlyingToken,
                _supplier,
                remainingToWithdraw
            );

        /* If there remains some tokens to withdraw, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToWithdraw > 0)
            _withdrawPositionFromP2P(poolToken, underlyingToken, _supplier, remainingToWithdraw);

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
    /// @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
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
        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Aave */
        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0)
            remainingToRepay -= _repayPositionToPool(
                poolToken,
                underlyingToken,
                _user,
                remainingToRepay
            );

        /* If there remains some tokens to repay, Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToRepay > 0)
            _repayPositionToP2P(poolToken, underlyingToken, _user, remainingToRepay);

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    /// @dev Supplies `_amount` for a `_user` on a specific market to the pool.
    /// @param _poolToken The pool token of the market the user wants to supply to.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _supplyPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        supplyBalanceInOf[poolTokenAddress][_user].onPool += _amount.divWadByRay(normalizedIncome); // Scaled Balance
        _updateSuppliers(poolTokenAddress, _user);
        _supplyERC20ToPool(_underlyingToken, _amount); // Revert on error
    }

    /// @dev Supplies up to `_amount` for a `_user` on a specific market to P2P.
    /// @param _poolToken The pool token of the market the user wants to supply to.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return matched The amount matched by the borrowers waiting on Pool.
    function _supplyPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );
        matched = _matchBorrowers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            supplyBalanceInOf[poolTokenAddress][_user].inP2P += matched.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            _updateSuppliers(poolTokenAddress, _user);
        }
    }

    /// @dev Borrows `_amount` for `_user` from pool.
    /// @param _poolToken The pool token of the market the user wants to borrow from.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _borrowPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        borrowBalanceInOf[poolTokenAddress][_user].onPool += _amount.divWadByRay(
            normalizedVariableDebt
        ); // In adUnit
        _updateBorrowers(poolTokenAddress, _user);
        _borrowERC20FromPool(_underlyingToken, _amount);
    }

    /// @dev Borrows up to `_amount` for `_user` from P2P.
    /// @param _poolToken The pool token of the market the user wants to borrow from.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return matched The amount matched by the suppliers waiting on Pool.
    function _borrowPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );
        matched = _matchSuppliers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            borrowBalanceInOf[poolTokenAddress][_user].inP2P += matched.divWadByRay(
                borrowP2PExchangeRate
            ); // In p2pUnit
            _updateBorrowers(poolTokenAddress, _user);
        }
    }

    /// @dev Withdraws `_amount` of the position of a `_user` on a specific market.
    /// @param _poolToken The pool token of the market the user wants to withdraw from.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @return withdrawnInUnderlying The amount withdrawn from the pool.
    function _withdrawPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 withdrawnInUnderlying) {
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 onPoolSupply = supplyBalanceInOf[poolTokenAddress][_user].onPool;
        uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
        withdrawnInUnderlying = Math.min(
            Math.min(onPoolSupplyInUnderlying, _amount),
            _poolToken.balanceOf(address(this))
        );

        supplyBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
            onPoolSupply,
            withdrawnInUnderlying.divWadByRay(normalizedIncome)
        ); // In poolToken
        _updateSuppliers(poolTokenAddress, _user);
        if (withdrawnInUnderlying > 0)
            _withdrawERC20FromPool(_underlyingToken, withdrawnInUnderlying); // Revert on error
    }

    /// @dev Withdraws `_amount` from the position of a `_user` in P2P.
    /// @param _poolToken The pool token of the market the user wants to withdraw from.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    function _withdrawPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );

        supplyBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
            supplyBalanceInOf[poolTokenAddress][_user].inP2P,
            _amount.divWadByRay(supplyP2PExchangeRate)
        ); // In p2pUnit
        _updateSuppliers(poolTokenAddress, _user);
        uint256 matchedSupply = _matchSuppliers(_poolToken, _underlyingToken, _amount);

        // We break some P2P credit lines the supplier had with borrowers and fallback on Aave.
        if (_amount > matchedSupply) _unmatchBorrowers(poolTokenAddress, _amount - matchedSupply); // Revert on error
    }

    /// @dev Repays `_amount` of the position of a `_user` on pool.
    /// @param _poolToken The pool token of the market the user wants to repay a position to.
    /// @param _underlyingToken The underlying token of the market to repay a position to.
    /// @param _user The address of the user.
    /// @param _amount The amount of tokens to repay (in underlying).
    /// @return repaidInUnderlying The amount repaid to the pool.
    function _repayPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal returns (uint256 repaidInUnderlying) {
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 borrowedOnPool = borrowBalanceInOf[poolTokenAddress][_user].onPool;
        uint256 borrowedOnPoolInUnderlying = borrowedOnPool.mulWadByRay(normalizedVariableDebt);
        repaidInUnderlying = Math.min(borrowedOnPoolInUnderlying, _amount);

        borrowBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
            borrowedOnPool,
            repaidInUnderlying.divWadByRay(normalizedVariableDebt)
        ); // In adUnit
        _updateBorrowers(poolTokenAddress, _user);
        if (repaidInUnderlying > 0)
            _repayERC20ToPool(_underlyingToken, repaidInUnderlying, normalizedVariableDebt); // Revert on error
    }

    /// @dev Repays `_amount` of the position of a `_user` in P2P.
    /// @param _poolToken The pool token of the market the user wants to repay a position to.
    /// @param _underlyingToken The underlying token of the market to repay a position to.
    /// @param _user The address of user.
    /// @param _amount The amount of token (in underlying).
    function _repayPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _user,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );

        borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
            borrowBalanceInOf[poolTokenAddress][_user].inP2P,
            _amount.divWadByRay(borrowP2PExchangeRate)
        ); // In p2pUnit
        _updateBorrowers(poolTokenAddress, _user);
        uint256 matchedBorrow = _matchBorrowers(_poolToken, _underlyingToken, _amount);

        // We break some P2P credit lines the borrower had with suppliers and fallback on Aave.
        if (_amount > matchedBorrow) _unmatchSuppliers(poolTokenAddress, _amount - matchedBorrow); // Revert on error
    }

    /// @dev Supplies undelrying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(IERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(IERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(IERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        (, , address variableDebtToken) = dataProvider.getReserveTokensAddresses(
            address(_underlyingToken)
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)).mulWadByRay(
                _normalizedVariableDebt
            )
        );
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }

    /// @dev Matches suppliers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The token amount to search for (in underlying).
    /// @return matchedSupply The amount of liquidity matched (in underlying).
    function _matchSuppliers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256 matchedSupply) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address user = suppliersOnPool[poolTokenAddress].getHead();
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );
        uint256 iterationCount;

        while (matchedSupply < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = supplyBalanceInOf[poolTokenAddress][user]
            .onPool
            .mulWadByRay(normalizedIncome);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedSupply);
            matchedSupply += toMatch;
            supplyBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            _updateSuppliers(poolTokenAddress, user);
            emit SupplierPositionUpdated(
                user,
                poolTokenAddress,
                supplyBalanceInOf[poolTokenAddress][user].onPool,
                supplyBalanceInOf[poolTokenAddress][user].inP2P
            );
            user = suppliersOnPool[poolTokenAddress].getHead();
        }

        if (matchedSupply > 0) {
            matchedSupply = Math.min(matchedSupply, _poolToken.balanceOf(address(this)));
            _withdrawERC20FromPool(_underlyingToken, matchedSupply); // Revert on error
        }
    }

    /// @dev Unmatches suppliers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    function _unmatchSuppliers(address _poolTokenAddress, uint256 _amount) internal {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            _poolTokenAddress
        );
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount; // In underlying

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][user].inP2P; // In poolToken
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(supplyP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            supplyBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            _updateSuppliers(_poolTokenAddress, user);
            emit SupplierPositionUpdated(
                user,
                _poolTokenAddress,
                supplyBalanceInOf[_poolTokenAddress][user].onPool,
                supplyBalanceInOf[_poolTokenAddress][user].inP2P
            );
            user = suppliersInP2P[_poolTokenAddress].getHead();
        }

        // Supply the remaining on Aave
        uint256 toSupply = _amount - remainingToUnmatch;
        if (toSupply > 0) _supplyERC20ToPool(underlyingToken, toSupply); // Revert on error
    }

    /// @dev Matches borrowers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The amount to search for (in underlying).
    /// @return matchedBorrow The amount of liquidity matched (in underlying).
    function _matchBorrowers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256 matchedBorrow) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );
        address user = borrowersOnPool[poolTokenAddress].getHead();
        uint256 iterationCount;

        while (matchedBorrow < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = borrowBalanceInOf[poolTokenAddress][user]
            .onPool
            .mulWadByRay(normalizedVariableDebt);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedBorrow);
            matchedBorrow += toMatch;
            borrowBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                borrowP2PExchangeRate
            );
            _updateBorrowers(poolTokenAddress, user);
            emit BorrowerPositionUpdated(
                user,
                poolTokenAddress,
                borrowBalanceInOf[poolTokenAddress][user].onPool,
                borrowBalanceInOf[poolTokenAddress][user].inP2P
            );
            user = borrowersOnPool[poolTokenAddress].getHead();
        }

        if (matchedBorrow > 0)
            _repayERC20ToPool(_underlyingToken, matchedBorrow, normalizedVariableDebt); // Revert on error
    }

    /// @dev Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    function _unmatchBorrowers(address _poolTokenAddress, uint256 _amount) internal {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            _poolTokenAddress
        );
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][user].inP2P;
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(borrowP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            borrowBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                borrowP2PExchangeRate
            );
            _updateBorrowers(_poolTokenAddress, user);
            emit BorrowerPositionUpdated(
                user,
                _poolTokenAddress,
                borrowBalanceInOf[_poolTokenAddress][user].onPool,
                borrowBalanceInOf[_poolTokenAddress][user].inP2P
            );
            user = borrowersInP2P[_poolTokenAddress].getHead();
        }

        uint256 toBorrow = _amount - remainingToUnmatch;
        if (toBorrow > 0) _borrowERC20FromPool(underlyingToken, toBorrow); // Revert on error
    }

    /// @dev Checks that the total supply of `supplier` is below the cap on a specific market.
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
        uint256 totalSuppliedInUnderlying = _getUserSupplyBalanceInOf(
            _poolTokenAddress,
            _supplier,
            address(_underlyingToken)
        );

        if (totalSuppliedInUnderlying + _amount > capValue[_poolTokenAddress])
            revert SupplyAboveCapValue();
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
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
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
                marketsManagerForAave.supplyP2PExchangeRate(_poolTokenAddress)
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedIncome(_underlyingTokenAddress)
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
                marketsManagerForAave.borrowP2PExchangeRate(_poolTokenAddress)
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(_underlyingTokenAddress)
            );
    }

    /// @dev Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the borrower to move.
    function _updateBorrowers(address _poolTokenAddress, address _user) internal {
        address(matchingEngineManager).functionDelegateCall(
            abi.encodeWithSelector(
                matchingEngineManager.updateBorrowers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }

    /// @dev Updates suppliers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the supplier to move.
    function _updateSuppliers(address _poolTokenAddress, address _user) internal {
        address(matchingEngineManager).functionDelegateCall(
            abi.encodeWithSelector(
                matchingEngineManager.updateSuppliers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }
}
