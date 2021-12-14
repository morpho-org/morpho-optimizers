// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";
import "./libraries/ErrorsForAave.sol";
import "./interfaces/aave/IPriceOracleGetter.sol";
import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IGetterIncentivesController.sol";

/**
 *  @title PositionsManagerForAave
 *  @dev Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using poolToken tokens.
 */
contract PositionsManagerForAave is ReentrancyGuard {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    // Struct to avoid stack too deep error
    struct BalanceStateVars {
        uint256 debtValue; // The total debt value (in ETH).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in ETH).
        uint256 debtToAdd; // The debt to add at the current iteration (in ETH).
        uint256 collateralToAdd; // The collateral to add at the current iteration (in ETH).
        uint256 p2pExchangeRate; // The p2pUnit exchange rate of the `poolTokenEntered`.
        uint256 underlyingPrice; // The price of the underlying linked to the `poolTokenEntered` (in ETH).
        uint256 normalizedVariableDebt; // Normalized variable debt of the market.
        uint256 normalizedIncome; // Normalized income of the market.
        uint256 liquidationThreshold; // The liquidation threshold on Aave.
        uint256 reserveDecimals; // The number of decimals of the asset in the reserve.
        uint256 tokenUnit; // The unit of tokens considering its decimals.
        address poolTokenEntered; // The poolToken token entered by the user.
        address underlyingAddress; // The address of the underlying.
        IPriceOracleGetter oracle; // Aave oracle.
    }

    // Struct to avoid stack too deep error
    struct LiquidateVars {
        uint256 debtValue; // The debt value (in ETH).
        uint256 maxDebtValue; // The maximum debt value possible (in ETH).
        uint256 borrowBalance; // Total borrow balance of the user for a given asset (in underlying).
        uint256 amountToSeize; // The amount of collateral the liquidator can seize (in underlying).
        uint256 borrowedPrice; // The price of the asset borrowed (in ETH).
        uint256 collateralPrice; // The price of the collateral asset (in ETH).
        uint256 normalizedIncome; // The normalized income of the asset.
        uint256 totalCollateral; // The total of collateral of the user (in underlying).
        uint256 liquidationBonus; // The liquidation bonus on Aave.
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The unit of collateral token considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
        address tokenBorrowedAddress; // The address of the borrowed asset.
        address tokenCollateralAddress; // The address of the collateral asset.
        IPriceOracleGetter oracle; // Aave oracle.
    }

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In p2pUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In p2pUnit.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    /* Storage */

    uint16 public NMAX = 1000;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // In basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Aave.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.
    mapping(address => uint256) public capValue; // Caps above the ones suppliers cannot add more liquidity.

    IMarketsManagerForAave public immutable marketsManagerForAave;
    ILendingPoolAddressesProvider public addressesProvider;
    IProtocolDataProvider public dataProvider;
    ILendingPool public lendingPool;

    /* Events */

    /** @dev Emitted when a supply happens.
     *  @param _account The address of the supplier.
     *  @param _poolTokenAddress The address of the market where assets are supplied into.
     *  @param _amount The amount of assets.
     */
    event Supplied(address indexed _account, address indexed _poolTokenAddress, uint256 _amount);

    /** @dev Emitted when a withdraw happens.
     *  @param _account The address of the withdrawer.
     *  @param _poolTokenAddress The address of the market from where assets are withdrawn.
     *  @param _amount The amount of assets.
     */
    event Withdrawn(address indexed _account, address indexed _poolTokenAddress, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _poolTokenAddress The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrowed(address indexed _account, address indexed _poolTokenAddress, uint256 _amount);

    /** @dev Emitted when a repay happens.
     *  @param _account The address of the repayer.
     *  @param _poolTokenAddress The address of the market where assets are repaid.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _poolTokenAddress, uint256 _amount);

    /** @dev Emitted when a liquidation happens.
     *  @param _liquidator The address of the liquidator.
     *  @param _liquidatee The address of the liquidatee.
     *  @param _amountRepaid The amount of borrowed asset repaid.
     *  @param _poolTokenBorrowedAddress The address of the borrowed asset.
     *  @param _amountSeized The amount of collateral asset seized.
     *  @param _poolTokenCollateralAddress The address of the collateral asset seized.
     */
    event Liquidated(
        address indexed _liquidator,
        address indexed _liquidatee,
        uint256 _amountRepaid,
        address _poolTokenBorrowedAddress,
        uint256 _amountSeized,
        address _poolTokenCollateralAddress
    );

    /** @dev Emitted when the position of a supplier is updated.
     *  @param _account The address of the supplier.
     *  @param _poolTokenAddress The address of the market.
     *  @param _amountAddedOnPool The amount added on pool (in underlying).
     *  @param _amountAddedInP2P The amount added in P2P (in underlying).
     *  @param _amountRemovedFromPool The amount removed from the pool (in underlying).
     *  @param _amountRemovedFromP2P The amount removed from P2P (in underlying).
     *  @param _p2pExchangeRate The P2P exchange rate at the moment.
     *  @param _normalizedIncome The normalized income at the moment.
     */
    event SupplierPositionUpdated(
        address indexed _account,
        address indexed _poolTokenAddress,
        uint256 _amountAddedOnPool,
        uint256 _amountAddedInP2P,
        uint256 _amountRemovedFromPool,
        uint256 _amountRemovedFromP2P,
        uint256 _p2pExchangeRate,
        uint256 _normalizedIncome
    );

    /** @dev Emitted when the position of a borrower is updated.
     *  @param _account The address of the borrower.
     *  @param _poolTokenAddress The address of the market.
     *  @param _amountAddedOnPool The amount added on pool (in underlying).
     *  @param _amountAddedInP2P The amount added in P2P (in underlying).
     *  @param _amountRemovedFromPool The amount removed from the pool (in underlying).
     *  @param _amountRemovedFromP2P The amount removed from P2P (in underlying).
     *  @param _p2pExchangeRate The P2P exchange rate at the moment.
     *  @param _normalizedVariableDebt The normalized variable debt at the moment.
     */
    event BorrowerPositionUpdated(
        address indexed _account,
        address indexed _poolTokenAddress,
        uint256 _amountAddedOnPool,
        uint256 _amountAddedInP2P,
        uint256 _amountRemovedFromPool,
        uint256 _amountRemovedFromP2P,
        uint256 _p2pExchangeRate,
        uint256 _normalizedVariableDebt
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not created yet.
     *  @param _poolTokenAddress The address of the market.
     */
    modifier isMarketCreated(address _poolTokenAddress) {
        require(marketsManagerForAave.isCreated(_poolTokenAddress), Errors.PM_MARKET_NOT_CREATED);
        _;
    }

    /** @dev Prevents a user to supply or borrow less than threshold.
     *  @param _poolTokenAddress The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _poolTokenAddress, uint256 _amount) {
        require(_amount >= threshold[_poolTokenAddress], Errors.PM_AMOUNT_NOT_ABOVE_THRESHOLD);
        _;
    }

    /** @dev Prevents a user to call function allowed for the markets manager..
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(marketsManagerForAave), Errors.PM_ONLY_MARKETS_MANAGER);
        _;
    }

    /* Constructor */

    /** @dev Constructs the PositionsManagerForAave contract.
     *  @param _marketsManager The address of the aave markets manager.
     *  @param _lendingPoolAddressesProvider The address of the lending pool addresses provider.
     */
    constructor(address _marketsManager, address _lendingPoolAddressesProvider) {
        marketsManagerForAave = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
    }

    /* External */

    /** @dev Updates the lending pool and the data provider.
     */
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
    }

    /** @dev Sets the maximum number of users in tree.
     *  @param _newMaxNumber The maximum number of users to have in the tree.
     */
    function setMaxNumberOfUsersInTree(uint16 _newMaxNumber) external onlyMarketsManager {
        NMAX = _newMaxNumber;
    }

    /** @dev Sets the threshold of a market.
     *  @param _poolTokenAddress The address of the market to set the threshold.
     *  @param _newThreshold The new threshold.
     */
    function setThreshold(address _poolTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_poolTokenAddress] = _newThreshold;
    }

    /** @dev Sets the max cap of a market.
     *  @param _poolTokenAddress The address of the market to set the threshold.
     *  @param _newCapValue The new threshold.
     */
    function setCapValue(address _poolTokenAddress, uint256 _newCapValue)
        external
        onlyMarketsManager
    {
        capValue[_poolTokenAddress] = _newCapValue;
    }

    /** @dev Claims rewards from liquidity mining and transfers them to the DAO.
     *  @param _asset The asset to get the rewards from (aToken or variable debt token).
     */
    function claimRewards(address _asset) external {
        address[] memory asset = new address[](1);
        asset[0] = _asset;
        IAaveIncentivesController(IGetterIncentivesController(_asset).getIncentivesController())
            .claimRewards(asset, type(uint256).max, marketsManagerForAave.owner());
    }

    /** @dev Supplies ERC20 tokens in a specific market.
     *  @param _poolTokenAddress The address of the market the user wants to supply.
     *  @param _amount The amount to supply in ERC20 tokens.
     */
    function supply(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Supplied(msg.sender, _poolTokenAddress, _amount);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 p2pExchangeRate = marketsManagerForAave.updateP2PUnitExchangeRate(
            _poolTokenAddress
        );
        uint256 totalSuppliedInUnderlying = supplyBalanceInOf[_poolTokenAddress][msg.sender]
            .inP2P
            .mulWadByRay(p2pExchangeRate) +
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool.mulWadByRay(normalizedIncome);
        require(
            totalSuppliedInUnderlying + _amount <= capValue[_poolTokenAddress],
            Errors.PM_SUPPLY_ABOVE_CAP_VALUE
        );
        /* DEFAULT CASE: There aren't any borrowers waiting on Aave, Morpho supplies all the tokens to Aave */
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Aave, Morpho matches the supplier in P2P with them as much as possible */
        if (borrowersOnPool[_poolTokenAddress].getHead() != address(0)) {
            remainingToSupplyToPool = _matchBorrowers(_poolTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToSupplyToPool;
            if (matched > 0) {
                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    p2pExchangeRate
                ); // In p2pUnit
                emit SupplierPositionUpdated(
                    msg.sender,
                    _poolTokenAddress,
                    0,
                    matched,
                    0,
                    0,
                    p2pExchangeRate,
                    0
                );
                _updateSupplierList(_poolTokenAddress, msg.sender);
            }
        }

        /* If there aren't enough borrowers waiting on Aave to match all the tokens supplied, the rest is supplied to Aave */
        if (remainingToSupplyToPool > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool
                .divWadByRay(normalizedIncome); // Scaled Balance
            _supplyERC20ToAave(_poolTokenAddress, remainingToSupplyToPool); // Revert on error
            emit SupplierPositionUpdated(
                msg.sender,
                _poolTokenAddress,
                remainingToSupplyToPool,
                0,
                0,
                0,
                0,
                normalizedIncome
            );
            _updateSupplierList(_poolTokenAddress, msg.sender);
        }
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _poolTokenAddress The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkAccountLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        emit Borrowed(msg.sender, _poolTokenAddress, _amount);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        /* DEFAULT CASE: There aren't any borrowers waiting on Aave, Morpho borrows all the tokens from Aave */
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Aave, Morpho matches the borrower in P2P with them as much as possible */
        if (suppliersOnPool[_poolTokenAddress].getHead() != address(0)) {
            // No need to update p2pUnitExchangeRate here as it's done in `_checkAccountLiquidity`
            uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
            remainingToBorrowOnPool = _matchSuppliers(_poolTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToBorrowOnPool;

            if (matched > 0) {
                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    p2pExchangeRate
                ); // In p2pUnit
                emit BorrowerPositionUpdated(
                    msg.sender,
                    _poolTokenAddress,
                    0,
                    matched,
                    0,
                    0,
                    p2pExchangeRate,
                    0
                );
                _updateBorrowerList(_poolTokenAddress, msg.sender);
            }
        }

        /* If there aren't enough suppliers waiting on Aave to match all the tokens borrowed, the rest is borrowed from Aave */
        if (remainingToBorrowOnPool > 0) {
            lendingPool.borrow(
                address(underlyingToken),
                remainingToBorrowOnPool,
                2,
                0,
                address(this)
            );
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool
                .divWadByRay(normalizedVariableDebt); // In adUnit
            emit BorrowerPositionUpdated(
                msg.sender,
                _poolTokenAddress,
                remainingToBorrowOnPool,
                0,
                0,
                0,
                normalizedVariableDebt,
                0
            );
            _updateBorrowerList(_poolTokenAddress, msg.sender);
        }
        underlyingToken.safeTransfer(msg.sender, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        _withdraw(_poolTokenAddress, _amount, msg.sender, msg.sender);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        _repay(_poolTokenAddress, msg.sender, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _poolTokenBorrowedAddress The address of the debt token the liquidator wants to repay.
     *  @param _poolTokenCollateralAddress The address of the collateral the liquidator wants to seize.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        require(_amount > 0, Errors.PM_AMOUNT_IS_0);
        LiquidateVars memory vars;
        (vars.debtValue, vars.maxDebtValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        require(vars.debtValue > vars.maxDebtValue, Errors.PM_DEBT_VALUE_NOT_ABOVE_MAX);
        IAToken poolTokenBorrowed = IAToken(_poolTokenBorrowedAddress);
        IAToken poolTokenCollateral = IAToken(_poolTokenCollateralAddress);
        vars.tokenBorrowedAddress = poolTokenBorrowed.UNDERLYING_ASSET_ADDRESS();
        vars.tokenCollateralAddress = poolTokenCollateral.UNDERLYING_ASSET_ADDRESS();
        vars.borrowBalance =
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(vars.tokenBorrowedAddress)
            ) +
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].inP2P.mulWadByRay(
                marketsManagerForAave.p2pUnitExchangeRate(_poolTokenBorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(LIQUIDATION_CLOSE_FACTOR_PERCENT).div(10000),
            Errors.PM_AMOUNT_ABOVE_ALLOWED_TO_REPAY
        ); // Same mechanism as Aave. Liquidator cannot repay more than part of the debt (cf close factor on Aave).

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
        vars.amountToSeize = _amount
            .mul(vars.borrowedPrice)
            .mul(vars.collateralTokenUnit)
            .mul(vars.liquidationBonus)
            .div(vars.borrowedTokenUnit)
            .div(vars.collateralPrice)
            .div(10000); // Same mechanism as aave. The collateral amount to seize is given.
        vars.normalizedIncome = lendingPool.getReserveNormalizedIncome(vars.tokenCollateralAddress);
        vars.totalCollateral =
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].onPool.mulWadByRay(
                vars.normalizedIncome
            ) +
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].inP2P.mulWadByRay(
                marketsManagerForAave.updateP2PUnitExchangeRate(_poolTokenCollateralAddress)
            );
        require(vars.amountToSeize <= vars.totalCollateral, Errors.PM_TO_SEIZE_ABOVE_COLLATERAL);
        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            vars.amountToSeize,
            _poolTokenCollateralAddress
        );
        _withdraw(_poolTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender);
    }

    /* Internal */

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     *  @param _holder The user to whom Morpho will withdraw the supply.
     *  @param _receiver The address of the user that will receive the tokens.
     */
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _holder,
        address _receiver
    ) internal isMarketCreated(_poolTokenAddress) {
        require(_amount > 0, Errors.PM_AMOUNT_IS_0);
        _checkAccountLiquidity(_holder, _poolTokenAddress, _amount, 0);
        emit Withdrawn(_holder, _poolTokenAddress, _amount);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Aave */
        if (supplyBalanceInOf[_poolTokenAddress][_holder].onPool > 0) {
            uint256 amountOnPoolInUnderlying = supplyBalanceInOf[_poolTokenAddress][_holder]
                .onPool
                .mulWadByRay(normalizedIncome);
            /* CASE 1: User withdraws less than his Aave supply balance */
            if (_amount <= amountOnPoolInUnderlying) {
                _withdrawERC20FromAave(_poolTokenAddress, _amount); // Revert on error
                supplyBalanceInOf[_poolTokenAddress][_holder].onPool -= _amount.divWadByRay(
                    normalizedIncome
                ); // In poolToken
                emit SupplierPositionUpdated(
                    _holder,
                    _poolTokenAddress,
                    0,
                    0,
                    _amount,
                    0,
                    0,
                    normalizedIncome
                );
                remainingToWithdraw = 0; // In underlying
            }
            /* CASE 2: User withdraws more than his Aave supply balance */
            else {
                _withdrawERC20FromAave(_poolTokenAddress, amountOnPoolInUnderlying); // Revert on error
                supplyBalanceInOf[_poolTokenAddress][_holder].onPool = 0;
                emit SupplierPositionUpdated(
                    _holder,
                    _poolTokenAddress,
                    0,
                    0,
                    amountOnPoolInUnderlying,
                    0,
                    0,
                    normalizedIncome
                );
                remainingToWithdraw = _amount - amountOnPoolInUnderlying; // In underlying
            }
            _updateSupplierList(_poolTokenAddress, _holder);
        }

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToWithdraw > 0) {
            uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
            uint256 aTokenContractBalance = poolToken.balanceOf(address(this));
            /* CASE 1: Other suppliers have enough tokens on Aave to compensate user's position */
            if (remainingToWithdraw <= aTokenContractBalance) {
                supplyBalanceInOf[_poolTokenAddress][_holder].inP2P -= Math.min(
                    supplyBalanceInOf[_poolTokenAddress][_holder].inP2P,
                    remainingToWithdraw.divWadByRay(p2pExchangeRate)
                ); // In p2pUnit
                _updateSupplierList(_poolTokenAddress, _holder);
                require(
                    _matchSuppliers(_poolTokenAddress, remainingToWithdraw) == 0,
                    Errors.PM_REMAINING_TO_MATCH_IS_NOT_0
                );
                emit SupplierPositionUpdated(
                    _holder,
                    _poolTokenAddress,
                    0,
                    0,
                    0,
                    remainingToWithdraw,
                    p2pExchangeRate,
                    0
                );
            }
            /* CASE 2: Other suppliers don't have enough tokens on Aave. Such scenario is called the Hard-Withdraw */
            else {
                supplyBalanceInOf[_poolTokenAddress][_holder].inP2P -= Math.min(
                    supplyBalanceInOf[_poolTokenAddress][_holder].inP2P,
                    remainingToWithdraw.divWadByRay(p2pExchangeRate)
                );
                _updateSupplierList(_poolTokenAddress, _holder);
                uint256 remaining = _matchSuppliers(_poolTokenAddress, aTokenContractBalance);
                emit SupplierPositionUpdated(
                    _holder,
                    _poolTokenAddress,
                    0,
                    0,
                    0,
                    remainingToWithdraw,
                    p2pExchangeRate,
                    0
                );
                remainingToWithdraw -= remaining;
                require(
                    _unmatchBorrowers(_poolTokenAddress, remainingToWithdraw) == 0, // We break some P2P credit lines the user had with borrowers and fallback on Aave.
                    Errors.PM_REMAINING_TO_UNMATCH_IS_NOT_0
                );
            }
        }
        underlyingToken.safeTransfer(_receiver, _amount);
    }

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrow.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _poolTokenAddress,
        address _borrower,
        uint256 _amount
    ) internal isMarketCreated(_poolTokenAddress) {
        require(_amount > 0, Errors.PM_AMOUNT_IS_0);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Aave */
        if (borrowBalanceInOf[_poolTokenAddress][_borrower].onPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            uint256 onPoolInUnderlying = borrowBalanceInOf[_poolTokenAddress][_borrower]
                .onPool
                .mulWadByRay(normalizedVariableDebt);
            /* CASE 1: User repays less than his Aave borrow balance */
            if (_amount <= onPoolInUnderlying) {
                underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
                lendingPool.repay(address(underlyingToken), _amount, 2, address(this));
                borrowBalanceInOf[_poolTokenAddress][_borrower].onPool -= _amount.divWadByRay(
                    normalizedVariableDebt
                ); // In adUnit
                remainingToRepay = 0;
                emit BorrowerPositionUpdated(
                    _borrower,
                    _poolTokenAddress,
                    0,
                    0,
                    _amount,
                    0,
                    0,
                    normalizedVariableDebt
                );
            }
            /* CASE 2: User repays more than his Aave borrow balance */
            else {
                underlyingToken.safeIncreaseAllowance(address(lendingPool), onPoolInUnderlying);
                lendingPool.repay(address(underlyingToken), onPoolInUnderlying, 2, address(this));
                borrowBalanceInOf[_poolTokenAddress][_borrower].onPool = 0;
                remainingToRepay -= onPoolInUnderlying; // In underlying
                emit BorrowerPositionUpdated(
                    _borrower,
                    _poolTokenAddress,
                    0,
                    0,
                    onPoolInUnderlying,
                    0,
                    0,
                    normalizedVariableDebt
                );
            }
            _updateBorrowerList(_poolTokenAddress, _borrower);
        }

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToRepay > 0) {
            DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
                address(underlyingToken)
            );
            IVariableDebtToken variableDebtToken = IVariableDebtToken(
                reserveData.variableDebtTokenAddress
            );
            uint256 p2pExchangeRate = marketsManagerForAave.updateP2PUnitExchangeRate(
                _poolTokenAddress
            );
            uint256 contractBorrowBalanceOnAave = variableDebtToken.scaledBalanceOf(address(this));
            /* CASE 1: Other borrowers are borrowing enough on Aave to compensate user's position */
            if (remainingToRepay <= contractBorrowBalanceOnAave) {
                borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P -= Math.min(
                    borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P,
                    remainingToRepay.divWadByRay(p2pExchangeRate)
                ); // In p2pUnit
                _updateBorrowerList(_poolTokenAddress, _borrower);
                _matchBorrowers(_poolTokenAddress, remainingToRepay);
                emit BorrowerPositionUpdated(
                    _borrower,
                    _poolTokenAddress,
                    0,
                    0,
                    0,
                    remainingToRepay,
                    p2pExchangeRate,
                    0
                );
            }
            /* CASE 2: Other borrowers aren't borrowing enough on Aave to compensate user's position */
            else {
                borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P -= Math.min(
                    borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P,
                    remainingToRepay.divWadByRay(p2pExchangeRate)
                ); // In p2pUnit
                _updateBorrowerList(_poolTokenAddress, _borrower);
                _matchBorrowers(_poolTokenAddress, remainingToRepay);
                emit BorrowerPositionUpdated(
                    _borrower,
                    _poolTokenAddress,
                    0,
                    0,
                    0,
                    remainingToRepay,
                    p2pExchangeRate,
                    0
                );
                remainingToRepay -= contractBorrowBalanceOnAave;
                require(
                    _unmatchSuppliers(_poolTokenAddress, remainingToRepay) == 0, // We break some P2P credit lines the user had with suppliers and fallback on Aave.
                    Errors.PM_REMAINING_TO_UNMATCH_IS_NOT_0
                );
            }
        }
        emit Repaid(_borrower, _poolTokenAddress, _amount);
    }

    /** @dev Supplies ERC20 tokens to Aave.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyERC20ToAave(address _poolTokenAddress, uint256 _amount) internal {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(underlyingToken), _amount, address(this), 0);
        lendingPool.setUserUseReserveAsCollateral(address(underlyingToken), true);
    }

    /** @dev Withdraws ERC20 tokens from Aave.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromAave(address _poolTokenAddress, uint256 _amount) internal {
        IAToken poolToken = IAToken(_poolTokenAddress);
        lendingPool.withdraw(poolToken.UNDERLYING_ASSET_ADDRESS(), _amount, address(this));
    }

    /** @dev Finds liquidity on Aave and matches it in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMatch The remaining liquidity to search for in underlying.
     */
    function _matchSuppliers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        IAToken poolToken = IAToken(_poolTokenAddress);
        remainingToMatch = _amount; // In underlying
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            poolToken.UNDERLYING_ASSET_ADDRESS()
        );
        address account = suppliersOnPool[_poolTokenAddress].getHead();
        uint256 iterationCount;

        while (remainingToMatch > 0 && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = supplyBalanceInOf[_poolTokenAddress][account]
                .onPool
                .mulWadByRay(normalizedIncome);
            uint256 toMatch = Math.min(onPoolInUnderlying, remainingToMatch);
            supplyBalanceInOf[_poolTokenAddress][account].onPool -= toMatch.divWadByRay(
                normalizedIncome
            );
            remainingToMatch -= toMatch;
            uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
            supplyBalanceInOf[_poolTokenAddress][account].inP2P += toMatch.divWadByRay(
                p2pExchangeRate
            ); // In p2pUnit
            _updateSupplierList(_poolTokenAddress, account);
            emit SupplierPositionUpdated(
                account,
                _poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                normalizedIncome
            );
            account = suppliersOnPool[_poolTokenAddress].getHead();
        }
        // Withdraw from Aave
        uint256 toWithdraw = _amount - remainingToMatch;
        if (toWithdraw > 0) _withdrawERC20FromAave(_poolTokenAddress, toWithdraw);
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Aave.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to unmatch in underlying.
     */
    function _unmatchSuppliers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        IAToken poolToken = IAToken(_poolTokenAddress);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            poolToken.UNDERLYING_ASSET_ADDRESS()
        );
        remainingToUnmatch = _amount; // In underlying
        uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
        address account = suppliersInP2P[_poolTokenAddress].getHead();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][account].inP2P; // In poolToken
            uint256 toUnmatch = Math.min(inP2P.mulWadByRay(p2pExchangeRate), remainingToUnmatch); // In underlying
            remainingToUnmatch -= toUnmatch;
            supplyBalanceInOf[_poolTokenAddress][account].onPool += toUnmatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[_poolTokenAddress][account].inP2P -= toUnmatch.divWadByRay(
                p2pExchangeRate
            ); // In p2pUnit
            _updateSupplierList(_poolTokenAddress, account);
            emit SupplierPositionUpdated(
                account,
                _poolTokenAddress,
                toUnmatch,
                0,
                0,
                toUnmatch,
                p2pExchangeRate,
                normalizedIncome
            );
            account = suppliersInP2P[_poolTokenAddress].getHead();
        }
        // Supply on Aave
        uint256 toSupply = _amount - remainingToUnmatch;
        if (toSupply > 0) _supplyERC20ToAave(_poolTokenAddress, _amount - remainingToUnmatch);
    }

    /** @dev Finds borrowers on Aave that match the given `_amount` and move them in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _matchBorrowers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        remainingToMatch = _amount;
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
        address account = borrowersOnPool[_poolTokenAddress].getHead();
        uint256 iterationCount;

        while (remainingToMatch > 0 && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = borrowBalanceInOf[_poolTokenAddress][account]
                .onPool
                .mulWadByRay(normalizedVariableDebt);
            uint256 toMatch = Math.min(onPoolInUnderlying, remainingToMatch);
            borrowBalanceInOf[_poolTokenAddress][account].onPool -= toMatch.divWadByRay(
                normalizedVariableDebt
            );
            remainingToMatch -= toMatch;
            borrowBalanceInOf[_poolTokenAddress][account].inP2P += toMatch.divWadByRay(
                p2pExchangeRate
            );
            _updateBorrowerList(_poolTokenAddress, account);
            emit BorrowerPositionUpdated(
                account,
                _poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                normalizedVariableDebt
            );
            account = borrowersOnPool[_poolTokenAddress].getHead();
        }
        // Repay Aave
        uint256 toRepay = _amount - remainingToMatch;
        if (toRepay > 0) {
            underlyingToken.safeIncreaseAllowance(address(lendingPool), toRepay);
            lendingPool.repay(address(underlyingToken), toRepay, 2, address(this));
        }
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Aave.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToUnmatch The amount remaining to unmatch in underlying.
     */
    function _unmatchBorrowers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        remainingToUnmatch = _amount;
        uint256 p2pExchangeRate = marketsManagerForAave.p2pUnitExchangeRate(_poolTokenAddress);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        address account = borrowersInP2P[_poolTokenAddress].getHead();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][account].inP2P;
            uint256 toUnmatch = Math.min(inP2P.mulWadByRay(p2pExchangeRate), remainingToUnmatch); // In underlying
            remainingToUnmatch -= toUnmatch;
            borrowBalanceInOf[_poolTokenAddress][account].onPool += toUnmatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[_poolTokenAddress][account].inP2P -= toUnmatch.divWadByRay(
                p2pExchangeRate
            );
            _updateBorrowerList(_poolTokenAddress, account);
            emit BorrowerPositionUpdated(
                account,
                _poolTokenAddress,
                toUnmatch,
                0,
                0,
                toUnmatch,
                p2pExchangeRate,
                normalizedVariableDebt
            );
            account = borrowersInP2P[_poolTokenAddress].getHead();
        }
        // Borrow on Aave
        lendingPool.borrow(
            address(underlyingToken),
            _amount - remainingToUnmatch,
            2,
            0,
            address(this)
        );
    }

    /**
     * @dev Enters the user into the market if he is not already there.
     * @param _account The address of the account to update.
     * @param _poolTokenAddress The address of the market to check.
     */
    function _handleMembership(address _poolTokenAddress, address _account) internal {
        if (!accountMembership[_poolTokenAddress][_account]) {
            accountMembership[_poolTokenAddress][_account] = true;
            enteredMarkets[_account].push(_poolTokenAddress);
        }
    }

    /** @dev Checks whether the user can borrow/withdraw or not.
     *  @param _account The user to determine liquidity for.
     *  @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     */
    function _checkAccountLiquidity(
        address _account,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
            _account,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        require(debtValue <= maxDebtValue, Errors.PM_DEBT_VALUE_ABOVE_MAX);
    }

    /** @dev Returns the debt value, max debt value and collateral value of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtValue, maxDebtValue).
     */
    function _getUserHypotheticalBalanceStates(
        address _account,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256, uint256) {
        // Avoid stack too deep error
        BalanceStateVars memory vars;
        vars.oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            vars.poolTokenEntered = enteredMarkets[_account][i];
            vars.p2pExchangeRate = marketsManagerForAave.updateP2PUnitExchangeRate(
                vars.poolTokenEntered
            );
            // Calculation of the current debt (in underlying)
            vars.underlyingAddress = IAToken(vars.poolTokenEntered).UNDERLYING_ASSET_ADDRESS();
            vars.normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                vars.underlyingAddress
            );
            vars.debtToAdd =
                borrowBalanceInOf[vars.poolTokenEntered][_account].onPool.mulWadByRay(
                    vars.normalizedVariableDebt
                ) +
                borrowBalanceInOf[vars.poolTokenEntered][_account].inP2P.mulWadByRay(
                    vars.p2pExchangeRate
                );
            // Calculation of the current collateral (in underlying)
            vars.normalizedIncome = lendingPool.getReserveNormalizedIncome(vars.underlyingAddress);
            vars.collateralToAdd =
                supplyBalanceInOf[vars.poolTokenEntered][_account].onPool.mulWadByRay(
                    vars.normalizedIncome
                ) +
                supplyBalanceInOf[vars.poolTokenEntered][_account].inP2P.mulWadByRay(
                    vars.p2pExchangeRate
                );
            vars.underlyingPrice = vars.oracle.getAssetPrice(vars.underlyingAddress); // In ETH

            (vars.reserveDecimals, , vars.liquidationThreshold, , , , , , , ) = dataProvider
                .getReserveConfigurationData(vars.underlyingAddress);
            vars.tokenUnit = 10**vars.reserveDecimals;
            // Conversion of the collateral to ETH
            vars.collateralToAdd = vars.collateralToAdd.mul(vars.underlyingPrice).div(
                vars.tokenUnit
            );
            vars.maxDebtValue += vars.collateralToAdd.mul(vars.liquidationThreshold).div(10000);
            vars.debtValue += vars.debtToAdd.mul(vars.underlyingPrice).div(vars.tokenUnit);
            if (_poolTokenAddress == vars.poolTokenEntered) {
                vars.debtValue += _borrowedAmount.mul(vars.underlyingPrice).div(vars.tokenUnit);
                vars.maxDebtValue -= _withdrawnAmount
                    .mul(vars.underlyingPrice)
                    .div(vars.tokenUnit)
                    .mul(vars.liquidationThreshold)
                    .div(10000);
            }
        }
        return (vars.debtValue, vars.maxDebtValue);
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function _updateBorrowerList(address _poolTokenAddress, address _account) internal {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            borrowersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function _updateSupplierList(address _poolTokenAddress, address _account) internal {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            suppliersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }
}
