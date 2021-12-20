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

    uint8 public NO_REFERRAL_CODE = 0;
    uint8 public VARIABLE_INTEREST_MODE = 2;
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

    /** @dev Prevents that the total supply of the supplier is above the cap.
     *  @param _poolTokenAddress The address of the market to check.
     *  @param _amount The amount to add to the current supply.
     */
    modifier isBelowCapValue(address _poolTokenAddress, uint256 _amount) {
        marketsManagerForAave.updateState(_poolTokenAddress);
        if (capValue[_poolTokenAddress] != type(uint256).max) {
            IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(_poolTokenAddress);
            uint256 totalSupplyInUnderlying = supplyBalanceInOf[_poolTokenAddress][msg.sender]
                .inP2P
                .mulWadByRay(p2pExchangeRate) +
                supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool.mulWadByRay(
                    normalizedIncome
                );
            require(
                totalSupplyInUnderlying + _amount <= capValue[_poolTokenAddress],
                Errors.PM_SUPPLY_ABOVE_CAP_VALUE
            );
        }
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
        isBelowCapValue(_poolTokenAddress, _amount)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _handleMembership(_poolTokenAddress, msg.sender);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Aave, Morpho matches the supplier in P2P with them as much as possible */
        if (borrowersOnPool[_poolTokenAddress].getHead() != address(0))
            remainingToSupplyToPool -= _supplyPositionToP2P(
                poolToken,
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough borrowers waiting on Aave to match all the tokens supplied, the rest is supplied to Aave */
        if (remainingToSupplyToPool > 0)
            _supplyPositionToPool(poolToken, underlyingToken, msg.sender, remainingToSupplyToPool);

        emit Supplied(msg.sender, _poolTokenAddress, _amount);
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
        marketsManagerForAave.updateState(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Aave, Morpho matches the borrower in P2P with them as much as possible */
        if (suppliersOnPool[_poolTokenAddress].getHead() != address(0))
            remainingToBorrowOnPool -= _borrowPositionFromP2P(
                poolToken,
                underlyingToken,
                msg.sender,
                _amount
            );

        /* If there aren't enough suppliers waiting on Aave to match all the tokens borrowed, the rest is borrowed from Aave */
        if (remainingToBorrowOnPool > 0)
            _borrowPositionFromPool(
                poolToken,
                underlyingToken,
                msg.sender,
                remainingToBorrowOnPool
            );

        underlyingToken.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _poolTokenAddress, _amount);
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
                marketsManagerForAave.p2pExchangeRate(_poolTokenBorrowedAddress)
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
        marketsManagerForAave.updateState(_poolTokenCollateralAddress);
        vars.totalCollateral =
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].onPool.mulWadByRay(
                vars.normalizedIncome
            ) +
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].inP2P.mulWadByRay(
                marketsManagerForAave.p2pExchangeRate(_poolTokenCollateralAddress)
            );
        require(vars.amountToSeize <= vars.totalCollateral, Errors.PM_TO_SEIZE_ABOVE_COLLATERAL);

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

    /* Internal */

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     *  @param _supplier The user to whom Morpho will withdraw the supply.
     *  @param _receiver The address of the user that will receive the tokens.
     */
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver
    ) internal isMarketCreated(_poolTokenAddress) {
        require(_amount > 0, Errors.PM_AMOUNT_IS_0);
        _checkAccountLiquidity(_supplier, _poolTokenAddress, _amount, 0);
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

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToWithdraw > 0)
            _withdrawPositionFromP2P(poolToken, underlyingToken, _supplier, remainingToWithdraw);

        underlyingToken.safeTransfer(_receiver, _amount);
        emit Withdrawn(_supplier, _poolTokenAddress, _amount);
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
        marketsManagerForAave.updateState(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Aave */
        if (borrowBalanceInOf[_poolTokenAddress][_borrower].onPool > 0)
            remainingToRepay -= _repayPositionToPool(
                poolToken,
                underlyingToken,
                _borrower,
                remainingToRepay
            );

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Aave itself */
        if (remainingToRepay > 0)
            _repayPositionToP2P(poolToken, underlyingToken, _borrower, remainingToRepay);

        emit Repaid(_borrower, _poolTokenAddress, _amount);
    }

    /** @dev Supplies `_amount` for a `_supplier` on a specific market to the pool.
     *  @param _poolToken The Aave interface of the market the user wants to supply to.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to supply to.
     *  @param _supplier The address of the supplier supplying the tokens.
     *  @param _amount The amount of ERC20 tokens to supply.
     */
    function _supplyPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        supplyBalanceInOf[poolTokenAddress][_supplier].onPool += _amount.divWadByRay(
            normalizedIncome
        ); // Scaled Balance
        _updateSupplierList(poolTokenAddress, _supplier);
        _supplyERC20ToPool(_underlyingToken, _amount); // Revert on error

        emit SupplierPositionUpdated(
            _supplier,
            poolTokenAddress,
            _amount,
            0,
            0,
            0,
            0,
            normalizedIncome
        );
    }

    /** @dev Supplies up to `_amount` for a `_supplier` on a specific market to P2P.
     *  @param _poolToken The Aave interface of the market the user wants to supply to.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to supply to.
     *  @param _supplier The address of the supplier supplying the tokens.
     *  @param _amount The amount of ERC20 tokens to supply.
     *  @return matched The amount matched by the borrowers waiting on Pool.
     */
    function _supplyPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);
        matched = _matchBorrowers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            supplyBalanceInOf[poolTokenAddress][_supplier].inP2P += matched.divWadByRay(
                p2pExchangeRate
            ); // In p2pUnit
            _updateSupplierList(poolTokenAddress, _supplier);

            emit SupplierPositionUpdated(
                _supplier,
                poolTokenAddress,
                0,
                matched,
                0,
                0,
                p2pExchangeRate,
                0
            );
        }
    }

    /** @dev Borrows `_amount` for `_borrower` from pool.
     *  @param _poolToken The Aave interface of the market the user wants to borrow from.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to borrow from.
     *  @param _borrower The address of the borrower who is borrowing.
     *  @param _amount The amount of ERC20 tokens to borrow.
     */
    function _borrowPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _borrower,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        borrowBalanceInOf[poolTokenAddress][_borrower].onPool += _amount.divWadByRay(
            normalizedVariableDebt
        ); // In adUnit
        _updateBorrowerList(poolTokenAddress, _borrower);
        _borrowERC20FromPool(_underlyingToken, _amount);

        emit BorrowerPositionUpdated(
            _borrower,
            poolTokenAddress,
            _amount,
            0,
            0,
            0,
            normalizedVariableDebt,
            0
        );
    }

    /** @dev Borrows up to `_amount` for `_borrower` from P2P.
     *  @param _poolToken The Aave interface of the market the user wants to borrow from.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to borrow from.
     *  @param _borrower The address of the borrower who is borrowing.
     *  @param _amount The amount of ERC20 tokens to borrow.
     *  @return matched The amount matched by the suppliers waiting on Pool.
     */
    function _borrowPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _borrower,
        uint256 _amount
    ) internal returns (uint256 matched) {
        address poolTokenAddress = address(_poolToken);
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);
        matched = _matchSuppliers(_poolToken, _underlyingToken, _amount); // In underlying

        if (matched > 0) {
            borrowBalanceInOf[poolTokenAddress][_borrower].inP2P += matched.divWadByRay(
                p2pExchangeRate
            ); // In p2pUnit
            _updateBorrowerList(poolTokenAddress, _borrower);

            emit BorrowerPositionUpdated(
                _borrower,
                poolTokenAddress,
                0,
                matched,
                0,
                0,
                p2pExchangeRate,
                0
            );
        }
    }

    /** @dev Withdraws `_amount` of the position of a `_supplier` on a specific market.
     *  @param _poolToken The Aave interface of the market the user wants to withdraw from.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to withdraw from.
     *  @param _supplier The address of the supplier to withdraw for.
     *  @param _amount The amount of ERC20 tokens to withdraw.
     *  @return withdrawnInUnderlying The amount withdrawn from the pool.
     */
    function _withdrawPositionFromPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal returns (uint256 withdrawnInUnderlying) {
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 onPoolSupply = supplyBalanceInOf[poolTokenAddress][_supplier].onPool;
        uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
        withdrawnInUnderlying = Math.min(onPoolSupplyInUnderlying, _amount);

        supplyBalanceInOf[poolTokenAddress][_supplier].onPool -= Math.min(
            onPoolSupply,
            withdrawnInUnderlying.divWadByRay(normalizedIncome)
        ); // In poolToken
        _updateSupplierList(poolTokenAddress, _supplier);
        if (withdrawnInUnderlying > 0)
            _withdrawERC20FromPool(_underlyingToken, withdrawnInUnderlying); // Revert on error

        emit SupplierPositionUpdated(
            _supplier,
            poolTokenAddress,
            0,
            0,
            withdrawnInUnderlying,
            0,
            0,
            normalizedIncome
        );
    }

    /** @dev Withdraws `_amount` of the position of a `_supplier` in peer-to-peer.
     *  @param _poolToken The Aave interface of the market the user wants to withdraw from.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to withdraw from.
     *  @param _supplier The address of the supplier to withdraw from.
     *  @param _amount The amount of ERC20 tokens to withdraw.
     */
    function _withdrawPositionFromP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _supplier,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);

        supplyBalanceInOf[poolTokenAddress][_supplier].inP2P -= Math.min(
            supplyBalanceInOf[poolTokenAddress][_supplier].inP2P,
            _amount.divWadByRay(p2pExchangeRate)
        ); // In p2pUnit
        _updateSupplierList(poolTokenAddress, _supplier);

        uint256 poolTokenContractBalance = _poolToken.balanceOf(address(this));
        uint256 supplyToMatch = Math.min(poolTokenContractBalance, _amount);
        uint256 matchedSupply;
        if (supplyToMatch > 0)
            matchedSupply = _matchSuppliers(_poolToken, _underlyingToken, supplyToMatch);

        require(
            // If the requested amount is less than what Morpho is supplying, liquidity should be totally available to withdraw because Morpho is supplying it.
            _amount > poolTokenContractBalance || matchedSupply == supplyToMatch,
            Errors.PM_COULD_NOT_MATCH_FULL_AMOUNT
        );

        if (_amount > matchedSupply) {
            uint256 remainingBorrowToUnmatch = _unmatchBorrowers(
                poolTokenAddress,
                _amount - matchedSupply
            ); // We break some P2P credit lines the supplier had with borrowers and fallback on Aave.
            require(remainingBorrowToUnmatch == 0, Errors.PM_COULD_NOT_UNMATCH_FULL_AMOUNT);
        }

        emit SupplierPositionUpdated(
            _supplier,
            poolTokenAddress,
            0,
            0,
            0,
            _amount,
            p2pExchangeRate,
            0
        );
    }

    /** @dev Implements withdraw logic.
     *  @param _poolToken The Aave interface of the market the user wants to repay a position to.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to repay a position to.
     *  @param _borrower The address of the borrower to repay the borrow of.
     *  @param _amount The amount of ERC20 tokens to repay.
     *  @return repaidInUnderlying The amount repaid to the pool.
     */
    function _repayPositionToPool(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _borrower,
        uint256 _amount
    ) internal returns (uint256 repaidInUnderlying) {
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        address poolTokenAddress = address(_poolToken);
        uint256 onPoolBorrow = borrowBalanceInOf[poolTokenAddress][_borrower].onPool;
        uint256 onPoolBorrowInUnderlying = onPoolBorrow.mulWadByRay(normalizedVariableDebt);
        repaidInUnderlying = Math.min(onPoolBorrowInUnderlying, _amount);

        borrowBalanceInOf[poolTokenAddress][_borrower].onPool -= Math.min(
            borrowBalanceInOf[poolTokenAddress][_borrower].onPool,
            repaidInUnderlying.divWadByRay(normalizedVariableDebt)
        ); // In adUnit
        _updateBorrowerList(poolTokenAddress, _borrower);
        if (repaidInUnderlying > 0) _repayERC20ToPool(_underlyingToken, repaidInUnderlying); // Revert on error

        emit BorrowerPositionUpdated(
            _borrower,
            poolTokenAddress,
            0,
            0,
            repaidInUnderlying,
            0,
            0,
            normalizedVariableDebt
        );
    }

    /** @dev Repays `_amount` of the position of a `_borrower` in peer-to-peer.
     *  @param _poolToken The Aave interface of the market the user wants to repay a position to.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to repay a position to.
     *  @param _borrower The address of the borrower to repay the borrow of.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repayPositionToP2P(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        address _borrower,
        uint256 _amount
    ) internal {
        address poolTokenAddress = address(_poolToken);
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);

        borrowBalanceInOf[poolTokenAddress][_borrower].inP2P -= Math.min(
            borrowBalanceInOf[poolTokenAddress][_borrower].inP2P,
            _amount.divWadByRay(p2pExchangeRate)
        ); // In p2pUnit
        _updateBorrowerList(poolTokenAddress, _borrower);
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            address(_underlyingToken)
        );
        IVariableDebtToken variableDebtToken = IVariableDebtToken(
            reserveData.variableDebtTokenAddress
        );
        uint256 debtTokenContractBalance = variableDebtToken.scaledBalanceOf(address(this));
        uint256 borrowToMatch = Math.min(debtTokenContractBalance, _amount);
        uint256 matchedBorrow;
        if (borrowToMatch > 0)
            matchedBorrow = _matchBorrowers(_poolToken, _underlyingToken, borrowToMatch);

        require(
            // If the requested amount is less than what Morpho is borrowing, liquidity should be totally available to repay because Morpho is borrowing it.
            _amount > debtTokenContractBalance || matchedBorrow == borrowToMatch,
            Errors.PM_COULD_NOT_MATCH_FULL_AMOUNT
        );

        if (_amount > matchedBorrow) {
            uint256 remainingSupplyToUnmatch = _unmatchSuppliers(
                poolTokenAddress,
                _amount - matchedBorrow
            ); // We break some P2P credit lines the borrower had with suppliers and fallback on Aave.

            require(remainingSupplyToUnmatch == 0, Errors.PM_COULD_NOT_UNMATCH_FULL_AMOUNT);
        }

        emit BorrowerPositionUpdated(
            _borrower,
            poolTokenAddress,
            0,
            0,
            0,
            _amount,
            p2pExchangeRate,
            0
        );
    }

    /** @dev Supplies ERC20 tokens to Aave.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to supply to.
     *  @param _amount The amount of tokens to supply.
     */
    function _supplyERC20ToPool(IERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
        lendingPool.setUserUseReserveAsCollateral(address(_underlyingToken), true);
    }

    /** @dev Withdraws ERC20 tokens from Aave.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to withdraw from.
     *  @param _amount The amount of tokens to withdraw.
     */
    function _withdrawERC20FromPool(IERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /** @dev Borrows ERC20 tokens to Aave.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to borrow from.
     *  @param _amount The amount of tokens to borrow.
     */
    function _borrowERC20FromPool(IERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /** @dev Repays ERC20 tokens to Aave.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to repay to.
     *  @param _amount The amount of tokens to repay.
     */
    function _repayERC20ToPool(IERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }

    /** @dev Finds liquidity on Aave and matches it in P2P.
     *  @dev Note: p2pExchangeRate must have been updated before calling this function.
     *  @param _poolToken The Aave interface of the market to find liquidity on.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to find liquidity.
     *  @param _amount The amount to search for in underlying.
     *  @return matchedSupply The amount of liquidity matched in underlying.
     */
    function _matchSuppliers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256 matchedSupply) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address account = suppliersOnPool[poolTokenAddress].getHead();
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);
        uint256 iterationCount;

        while (matchedSupply < _amount && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = supplyBalanceInOf[poolTokenAddress][account]
                .onPool
                .mulWadByRay(normalizedIncome);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedSupply);
            matchedSupply += toMatch;
            supplyBalanceInOf[poolTokenAddress][account].onPool -= toMatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[poolTokenAddress][account].inP2P += toMatch.divWadByRay(
                p2pExchangeRate
            ); // In p2pUnit
            _updateSupplierList(poolTokenAddress, account);
            emit SupplierPositionUpdated(
                account,
                poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                normalizedIncome
            );
            account = suppliersOnPool[poolTokenAddress].getHead();
        }

        if (matchedSupply > 0) _withdrawERC20FromPool(_underlyingToken, matchedSupply); // Revert on error
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Aave.
     *  @dev Note: p2pExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to unmatch in underlying.
     */
    function _unmatchSuppliers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        remainingToUnmatch = _amount; // In underlying
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(_poolTokenAddress);
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
        if (toSupply > 0) _supplyERC20ToPool(underlyingToken, _amount - remainingToUnmatch); // Revert on error
    }

    /** @dev Finds borrowers on Aave that match the given `_amount` and move them in P2P.
     *  @dev Note: p2pExchangeRate must have been updated before calling this function.
     *  @param _poolToken The Aave interface of the market to find liquidity on.
     *  @param _underlyingToken The ERC20 interface of the underlying token of the market to find liquidity.
     *  @param _amount The amount to search for in underlying.
     *  @return matchedBorrow The amount of liquidity matched in underlying.
     */
    function _matchBorrowers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256 matchedBorrow) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(poolTokenAddress);
        address account = borrowersOnPool[poolTokenAddress].getHead();
        uint256 iterationCount;

        while (matchedBorrow < _amount && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = borrowBalanceInOf[poolTokenAddress][account]
                .onPool
                .mulWadByRay(normalizedVariableDebt);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedBorrow);
            matchedBorrow += toMatch;
            borrowBalanceInOf[poolTokenAddress][account].onPool -= toMatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[poolTokenAddress][account].inP2P += toMatch.divWadByRay(
                p2pExchangeRate
            );
            _updateBorrowerList(poolTokenAddress, account);
            emit BorrowerPositionUpdated(
                account,
                poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                normalizedVariableDebt
            );
            account = borrowersOnPool[poolTokenAddress].getHead();
        }

        if (matchedBorrow > 0) _repayERC20ToPool(_underlyingToken, matchedBorrow); // Revert on error
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Aave.
     *  @dev Note: p2pExchangeRate must have been updated before calling this function.
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
        uint256 p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(_poolTokenAddress);
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

        _borrowERC20FromPool(underlyingToken, _amount - remainingToUnmatch);
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
            marketsManagerForAave.updateState(vars.poolTokenEntered);
            vars.p2pExchangeRate = marketsManagerForAave.p2pExchangeRate(vars.poolTokenEntered);
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
