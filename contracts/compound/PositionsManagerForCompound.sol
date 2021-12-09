// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/ErrorsForCompound.sol";
import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IMarketsManagerForCompound.sol";

/**
 *  @title MorphoPositionsManagerForComp?
 *  @dev Smart contract interacting with Comp to enable P2P supply/borrow positions that can fallback on Comp's pool using poolToken tokens.
 */
contract PositionsManagerForCompound is ReentrancyGuard {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In p2pUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onPool; // In poolToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In p2pUnit.
        uint256 onPool; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Comp. Multiply by current borrowIndex to get the underlying amount.
    }

    // Struct to avoid stack too deep error
    struct BalanceStateVars {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 debtToAdd; // The debt to add at the current iteration.
        uint256 collateralToAdd; // The collateral to add at the current iteration.
        address poolTokenEntered; // The poolToken token entered by the user.
        uint256 p2pExchangeRate; // The p2pUnit exchange rate of the `cErc20Entered`.
        uint256 underlyingPrice; // The price of the underlying linked to the `cErc20Entered`.
    }

    // Struct to avoid stack too deep error
    struct LiquidateVars {
        uint256 borrowBalance; // Total borrow balance of the user in underlying for a given asset.
        uint256 amountToSeize; // The amount of collateral underlying the liquidator can seize.
        uint256 priceBorrowedMantissa; // The price of the asset borrowed (in USD).
        uint256 priceCollateralMantissa; // The price of the collateral asset (in USD).
        uint256 collateralOnPoolInUnderlying; // The amount of underlying the liquidatee has on Comp.
    }

    /* Storage */

    uint16 public NMAX = 20;
    uint8 public constant CTOKEN_DECIMALS = 8;
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Comp.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Comp.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IComptroller public comptroller;
    IMarketsManagerForCompound public marketsManagerForCompound;

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
     *  @param _poolTokenExchangeRate The poolToken exchange rate at the moment.
     */
    event SupplierPositionUpdated(
        address indexed _account,
        address indexed _poolTokenAddress,
        uint256 _amountAddedOnPool,
        uint256 _amountAddedInP2P,
        uint256 _amountRemovedFromPool,
        uint256 _amountRemovedFromP2P,
        uint256 _p2pExchangeRate,
        uint256 _poolTokenExchangeRate
    );

    /** @dev Emitted when the position of a borrower is updated.
     *  @param _account The address of the borrower.
     *  @param _poolTokenAddress The address of the market.
     *  @param _amountAddedOnPool The amount added on pool (in underlying).
     *  @param _amountAddedInP2P The amount added in P2P (in underlying).
     *  @param _amountRemovedFromPool The amount removed from the pool (in underlying).
     *  @param _amountRemovedFromP2P The amount removed from P2P (in underlying).
     *  @param _p2pExchangeRate The P2P exchange rate at the moment.
     *  @param _borrowIndex The borrow index at the moment.
     */
    event BorrowerPositionUpdated(
        address indexed _account,
        address indexed _poolTokenAddress,
        uint256 _amountAddedOnPool,
        uint256 _amountAddedInP2P,
        uint256 _amountRemovedFromPool,
        uint256 _amountRemovedFromP2P,
        uint256 _p2pExchangeRate,
        uint256 _borrowIndex
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not created yet.
     *  @param _poolTokenAddress The address of the market.
     */
    modifier isMarketCreated(address _poolTokenAddress) {
        require(
            marketsManagerForCompound.isCreated(_poolTokenAddress),
            Errors.PM_MARKET_NOT_CREATED
        );
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

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(marketsManagerForCompound), Errors.PM_ONLY_MARKETS_MANAGER);
        _;
    }

    /* Constructor */

    /** @dev Constructs the PositionsManagerForCompound contract.
     *  @param _compoundMarketsManager The address of the markets manager.
     *  @param _proxyComptrollerAddress The address of the proxy comptroller.
     */
    constructor(address _compoundMarketsManager, address _proxyComptrollerAddress) {
        marketsManagerForCompound = IMarketsManagerForCompound(_compoundMarketsManager);
        comptroller = IComptroller(_proxyComptrollerAddress);
    }

    /* External */

    /** @dev Creates Comp's markets.
     *  @param _poolTokenAddress The address of the market the user wants to supply.
     *  @return The results of entered.
     */
    function createMarket(address _poolTokenAddress)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        return comptroller.enterMarkets(marketToEnter);
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
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Supplied(msg.sender, _poolTokenAddress, _amount);
        uint256 poolTokenExchangeRate = poolToken.exchangeRateCurrent();
        /* DEFAULT CASE: There aren't any borrowers waiting on Comp, Morpho supplies all the tokens to Comp */
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Comp, Morpho matches the supplier in P2P with them as much as possible */
        if (borrowersOnPool[_poolTokenAddress].getHead() != address(0)) {
            uint256 p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                _poolTokenAddress
            );
            remainingToSupplyToPool = _matchBorrowers(_poolTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToSupplyToPool;

            if (matched > 0) {
                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.div(
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

        /* If there aren't enough borrowers waiting on Comp to match all the tokens supplied, the rest is supplied to Comp */
        if (remainingToSupplyToPool > 0) {
            if (_isAboveCompoundThreshold(_poolTokenAddress, remainingToSupplyToPool)) {
                supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool
                    .div(poolTokenExchangeRate); // In poolToken
                _supplyERC20ToPool(_poolTokenAddress, remainingToSupplyToPool); // Revert on error
                emit SupplierPositionUpdated(
                    msg.sender,
                    _poolTokenAddress,
                    remainingToSupplyToPool,
                    0,
                    0,
                    0,
                    0,
                    poolTokenExchangeRate
                );
                _updateSupplierList(_poolTokenAddress, msg.sender);
            }
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
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        /* DEFAULT CASE: There aren't any borrowers waiting on Comp, Morpho borrows all the tokens from Comp */
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Comp, Morpho matches the borrower in P2P with them as much as possible */
        if (suppliersOnPool[_poolTokenAddress].getHead() != address(0)) {
            uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(
                _poolTokenAddress
            );
            remainingToBorrowOnPool = _matchSuppliers(_poolTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToBorrowOnPool;
            if (matched > 0) {
                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.div(
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

        /* If there aren't enough suppliers waiting on Comp to match all the tokens borrowed, the rest is borrowed from Comp */
        if (remainingToBorrowOnPool > 0) {
            require(poolToken.borrow(remainingToBorrowOnPool) == 0, Errors.PM_BORROW_ON_COMP_FAIL);
            uint256 borrowIndex = poolToken.borrowIndex();
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool.div(
                borrowIndex
            ); // In cdUnit
            emit BorrowerPositionUpdated(
                msg.sender,
                _poolTokenAddress,
                remainingToBorrowOnPool,
                0,
                0,
                0,
                borrowIndex,
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
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        require(debtValue > maxDebtValue, Errors.PM_DEBT_VALUE_NOT_ABOVE_MAX);
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].onPool.mul(
                ICErc20(_poolTokenBorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_poolTokenBorrowedAddress][_borrower].inP2P.mul(
                marketsManagerForCompound.p2pUnitExchangeRate(_poolTokenBorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(comptroller.closeFactorMantissa()),
            Errors.PM_AMOUNT_ABOVE_ALLOWED_TO_REPAY
        );

        _repay(_poolTokenBorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(
            _poolTokenCollateralAddress
        );
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        require(
            vars.priceCollateralMantissa != 0 && vars.priceBorrowedMantissa != 0,
            Errors.PM_TO_SEIZE_ABOVE_COLLATERAL
        );

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        // seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        // seizeTokens = seizeAmount / exchangeRate
        // = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        ICErc20 poolTokenCollateral = ICErc20(_poolTokenCollateralAddress);
        vars.amountToSeize = _amount
            .mul(vars.priceBorrowedMantissa)
            .mul(comptroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);
        vars.collateralOnPoolInUnderlying = supplyBalanceInOf[_poolTokenCollateralAddress][
            _borrower
        ].onPool.mul(poolTokenCollateral.exchangeRateStored());
        uint256 totalCollateral = vars.collateralOnPoolInUnderlying +
            supplyBalanceInOf[_poolTokenCollateralAddress][_borrower].inP2P.mul(
                marketsManagerForCompound.updateP2pUnitExchangeRate(_poolTokenCollateralAddress)
            );
        require(vars.amountToSeize <= totalCollateral, Errors.PM_TO_SEIZE_ABOVE_COLLATERAL);
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
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        uint256 poolTokenExchangeRate = poolToken.exchangeRateCurrent();
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Comp */
        if (supplyBalanceInOf[_poolTokenAddress][_holder].onPool > 0) {
            uint256 amountOnPoolInUnderlying = supplyBalanceInOf[_poolTokenAddress][_holder]
                .onPool
                .mul(poolTokenExchangeRate);
            /* CASE 1: User withdraws less than his Comp supply balance */
            if (_amount <= amountOnPoolInUnderlying) {
                if (_isAboveCompoundThreshold(_poolTokenAddress, _amount)) {
                    supplyBalanceInOf[_poolTokenAddress][_holder].onPool -= _amount.div(
                        poolTokenExchangeRate
                    ); // In poolToken
                    _withdrawERC20FromComp(_poolTokenAddress, _amount); // Revert on error
                    emit SupplierPositionUpdated(
                        _holder,
                        _poolTokenAddress,
                        0,
                        0,
                        _amount,
                        0,
                        0,
                        poolTokenExchangeRate
                    );
                }
                remainingToWithdraw = 0; // In underlying
            }
            /* CASE 2: User withdraws more than his Comp supply balance */
            else {
                require(
                    poolToken.redeem(supplyBalanceInOf[_poolTokenAddress][_holder].onPool) == 0,
                    Errors.PM_REDEEM_ON_COMP_FAIL
                );
                supplyBalanceInOf[_poolTokenAddress][_holder].onPool = 0;
                emit SupplierPositionUpdated(
                    _holder,
                    _poolTokenAddress,
                    0,
                    0,
                    amountOnPoolInUnderlying,
                    0,
                    0,
                    poolTokenExchangeRate
                );
                remainingToWithdraw = _amount - amountOnPoolInUnderlying; // In underlying
            }
            _updateSupplierList(_poolTokenAddress, _holder);
        }

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Comp itself */
        if (remainingToWithdraw > 0) {
            uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(
                _poolTokenAddress
            );
            uint256 poolTokenContractBalanceInUnderlying = poolToken.balanceOf(address(this)).mul(
                poolTokenExchangeRate
            );
            /* CASE 1: Other suppliers have enough tokens on Comp to compensate user's position */
            if (remainingToWithdraw <= poolTokenContractBalanceInUnderlying) {
                supplyBalanceInOf[_poolTokenAddress][_holder].inP2P -= Math.min(
                    supplyBalanceInOf[_poolTokenAddress][_holder].inP2P,
                    remainingToWithdraw.div(p2pExchangeRate)
                ); // In p2pUnit                _updateSupplierList(_poolTokenAddress, _holder);
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
            /* CASE 2: Other suppliers don't have enough tokens on Comp. Such scenario is called the Hard-Withdraw */
            else {
                supplyBalanceInOf[_poolTokenAddress][_holder].inP2P -= Math.min(
                    supplyBalanceInOf[_poolTokenAddress][_holder].inP2P,
                    remainingToWithdraw.div(p2pExchangeRate)
                ); // In p2pUnit
                _updateSupplierList(_poolTokenAddress, _holder);
                uint256 remaining = _matchSuppliers(
                    _poolTokenAddress,
                    poolTokenContractBalanceInUnderlying
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
                remainingToWithdraw -= remaining;
                require(
                    _unmatchBorrowers(_poolTokenAddress, remainingToWithdraw) == 0, // We break some P2P credit lines the user had with borrowers and fallback on Comp.
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
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Comp */
        if (borrowBalanceInOf[_poolTokenAddress][_borrower].onPool > 0) {
            uint256 borrowIndex = poolToken.borrowIndex();
            uint256 onPoolInUnderlying = borrowBalanceInOf[_poolTokenAddress][_borrower].onPool.mul(
                borrowIndex
            );
            /* CASE 1: User repays less than his Comp borrow balance */
            if (_amount <= onPoolInUnderlying) {
                underlyingToken.safeApprove(_poolTokenAddress, _amount);
                poolToken.repayBorrow(_amount);
                borrowBalanceInOf[_poolTokenAddress][_borrower].onPool -= _amount.div(borrowIndex); // In cdUnit
                remainingToRepay = 0;
                emit BorrowerPositionUpdated(
                    _borrower,
                    _poolTokenAddress,
                    0,
                    0,
                    _amount,
                    0,
                    0,
                    borrowIndex
                );
            }
            /* CASE 2: User repays more than his Comp borrow balance */
            else {
                underlyingToken.safeApprove(_poolTokenAddress, onPoolInUnderlying);
                poolToken.repayBorrow(onPoolInUnderlying); // Revert on error
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
                    borrowIndex
                );
            }
            _updateBorrowerList(_poolTokenAddress, _borrower);
        }

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Comp itself */
        if (remainingToRepay > 0) {
            uint256 p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                _poolTokenAddress
            );
            uint256 contractBorrowBalanceOnPool = poolToken.borrowBalanceCurrent(address(this)); // In underlying
            /* CASE 1: Other borrowers are borrowing enough on Comp to compensate user's position */
            if (remainingToRepay <= contractBorrowBalanceOnPool) {
                borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P -= Math.min(
                    borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P,
                    remainingToRepay.div(p2pExchangeRate)
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
            /* CASE 2: Other borrowers aren't borrowing enough on Comp to compensate user's position */
            else {
                borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P -= Math.min(
                    borrowBalanceInOf[_poolTokenAddress][_borrower].inP2P,
                    remainingToRepay.div(p2pExchangeRate)
                ); // In p2pUnit
                _updateBorrowerList(_poolTokenAddress, _borrower);
                _matchBorrowers(_poolTokenAddress, contractBorrowBalanceOnPool);
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
                remainingToRepay -= contractBorrowBalanceOnPool;
                require(
                    _unmatchSuppliers(_poolTokenAddress, remainingToRepay) == 0, // We break some P2P credit lines the user had with suppliers and fallback on Comp.
                    Errors.PM_REMAINING_TO_UNMATCH_IS_NOT_0
                );
            }
        }
        emit Repaid(_borrower, _poolTokenAddress, _amount);
    }

    /** @dev Supplies ERC20 tokens to Comp.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyERC20ToPool(address _poolTokenAddress, uint256 _amount) internal {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        underlyingToken.safeApprove(_poolTokenAddress, _amount);
        require(poolToken.mint(_amount) == 0, Errors.PM_MINT_ON_COMP_FAIL);
    }

    /** @dev Withdraws ERC20 tokens from Comp.
     *  @param _poolTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromComp(address _poolTokenAddress, uint256 _amount) internal {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        require(poolToken.redeemUnderlying(_amount) == 0, Errors.PM_REDEEM_ON_COMP_FAIL);
    }

    /** @dev Returns whether it is unsafe supply/witdhraw due to coumpound's revert on low levels of precision or not.
     *  @param _amount The amount of token considered for depositing/redeeming.
     *  @param _poolTokenAddress poolToken address of the considered market.
     *  @return Whether to continue or not.
     */
    function _isAboveCompoundThreshold(address _poolTokenAddress, uint256 _amount)
        internal
        view
        returns (bool)
    {
        IERC20Metadata token = IERC20Metadata(ICErc20(_poolTokenAddress).underlying());
        uint8 tokenDecimals = token.decimals();
        if (tokenDecimals > CTOKEN_DECIMALS)
            // Multiply by 2 to have a safety buffer
            return (_amount > 2 * 10**(tokenDecimals - CTOKEN_DECIMALS));
        else return true;
    }

    /** @dev Returns whether the amount is above the precision threshold.
     *  @param _amount The amount moved.
     *  @param _rate1 The first rate to compare the amount with.
     *  @param _rate2 The second rate to compare the amount with.
     *  @return Whether this is above threshold or not.
     */
    function _isAbovePrecisionThreshold(
        uint256 _amount,
        uint256 _rate1,
        uint256 _rate2
    ) internal pure returns (bool) {
        return (_amount > _rate1 / 1e18 && _amount > _rate2 / 1e18);
    }

    /** @dev Finds liquidity on Comp and matches it in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMatch The remaining liquidity to search for in underlying.
     */
    function _matchSuppliers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        remainingToMatch = _amount; // In underlying
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_poolTokenAddress);
        uint256 poolTokenExchangeRate = poolToken.exchangeRateCurrent();
        address account = suppliersOnPool[_poolTokenAddress].getHead();
        uint256 iterationCount;

        while (remainingToMatch > 0 && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            // Check if this user is not borrowing on Pool (cf Liquidation Invariant in docs)
            uint256 onPoolInUnderlying = supplyBalanceInOf[_poolTokenAddress][account].onPool.mul(
                poolTokenExchangeRate
            ); // In underlying
            uint256 toMatch = Math.min(onPoolInUnderlying, remainingToMatch);
            if (_isAbovePrecisionThreshold(toMatch, p2pExchangeRate, poolTokenExchangeRate)) {
                supplyBalanceInOf[_poolTokenAddress][account].onPool -= toMatch.div(
                    poolTokenExchangeRate
                ); // In poolToken
                supplyBalanceInOf[_poolTokenAddress][account].inP2P += toMatch.div(p2pExchangeRate); // In p2pUnit
            } else {
                supplyBalanceInOf[_poolTokenAddress][account].onPool = 0;
            }
            remainingToMatch -= toMatch;
            _updateSupplierList(_poolTokenAddress, account);
            emit SupplierPositionUpdated(
                account,
                _poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                poolTokenExchangeRate
            );
            account = suppliersOnPool[_poolTokenAddress].getHead();
        }
        // Withdraw from Comp
        uint256 toWithdraw = _amount - remainingToMatch;
        if (_isAboveCompoundThreshold(_poolTokenAddress, toWithdraw))
            _withdrawERC20FromComp(_poolTokenAddress, toWithdraw);
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Comp.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchSuppliers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        remainingToUnmatch = _amount; // In underlying
        uint256 poolTokenExchangeRate = poolToken.exchangeRateCurrent();
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_poolTokenAddress);
        address account = suppliersInP2P[_poolTokenAddress].getHead();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][account].inP2P; // In poolToken
            uint256 toUnmatch = Math.min(inP2P.mul(p2pExchangeRate), remainingToUnmatch); // In underlying
            if (_isAbovePrecisionThreshold(toUnmatch, p2pExchangeRate, poolTokenExchangeRate)) {
                supplyBalanceInOf[_poolTokenAddress][account].inP2P -= toUnmatch.div(
                    p2pExchangeRate
                ); // In p2pUnit
                supplyBalanceInOf[_poolTokenAddress][account].onPool += toUnmatch.div(
                    poolTokenExchangeRate
                ); // In poolToken
            } else {
                supplyBalanceInOf[_poolTokenAddress][account].inP2P = 0;
            }
            remainingToUnmatch -= toUnmatch;
            _updateSupplierList(_poolTokenAddress, account);
            emit SupplierPositionUpdated(
                account,
                _poolTokenAddress,
                toUnmatch,
                0,
                0,
                toUnmatch,
                p2pExchangeRate,
                poolTokenExchangeRate
            );
            account = suppliersInP2P[_poolTokenAddress].getHead();
        }
        // Supply on Comp
        uint256 toSupply = _amount - remainingToUnmatch;
        if (_isAboveCompoundThreshold(_poolTokenAddress, toSupply))
            _supplyERC20ToPool(_poolTokenAddress, toSupply);
    }

    /** @dev Finds borrowers on Comp that match the given `_amount` and move them in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _matchBorrowers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.underlying());
        remainingToMatch = _amount;
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_poolTokenAddress);
        uint256 borrowIndex = poolToken.borrowIndex();
        address account = borrowersOnPool[_poolTokenAddress].getHead();
        uint256 iterationCount;

        while (remainingToMatch > 0 && account != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = borrowBalanceInOf[_poolTokenAddress][account].onPool.mul(
                borrowIndex
            ); // In underlying
            uint256 toMatch = Math.min(onPoolInUnderlying, remainingToMatch);
            if (_isAbovePrecisionThreshold(toMatch, borrowIndex, p2pExchangeRate)) {
                borrowBalanceInOf[_poolTokenAddress][account].onPool -= toMatch.div(borrowIndex);
                borrowBalanceInOf[_poolTokenAddress][account].inP2P += toMatch.div(p2pExchangeRate);
            } else {
                borrowBalanceInOf[_poolTokenAddress][account].onPool = 0;
            }
            remainingToMatch -= toMatch;
            _updateBorrowerList(_poolTokenAddress, account);
            emit BorrowerPositionUpdated(
                account,
                _poolTokenAddress,
                0,
                toMatch,
                toMatch,
                0,
                p2pExchangeRate,
                borrowIndex
            );
            account = borrowersOnPool[_poolTokenAddress].getHead();
        }
        // Repay Comp
        uint256 toRepay = Math.min(
            _amount - remainingToMatch,
            poolToken.borrowBalanceCurrent(address(this))
        );
        underlyingToken.safeApprove(_poolTokenAddress, toRepay);
        require(poolToken.repayBorrow(toRepay) == 0, Errors.PM_REPAY_ON_COMP_FAIL);
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Comp.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _poolTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchBorrowers(address _poolTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 poolToken = ICErc20(_poolTokenAddress);
        remainingToUnmatch = _amount;
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_poolTokenAddress);
        uint256 borrowIndex = poolToken.borrowIndex();
        address account = borrowersInP2P[_poolTokenAddress].getHead();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][account].inP2P;
            uint256 toUnmatch = Math.min(inP2P.mul(p2pExchangeRate), remainingToUnmatch); // In underlying
            if (_isAbovePrecisionThreshold(toUnmatch, borrowIndex, p2pExchangeRate)) {
                borrowBalanceInOf[_poolTokenAddress][account].onPool += toUnmatch.div(borrowIndex);
                borrowBalanceInOf[_poolTokenAddress][account].inP2P -= toUnmatch.div(
                    p2pExchangeRate
                );
            } else {
                borrowBalanceInOf[_poolTokenAddress][account].inP2P = 0;
            }
            remainingToUnmatch -= toUnmatch;
            _updateBorrowerList(_poolTokenAddress, account);
            emit BorrowerPositionUpdated(
                account,
                _poolTokenAddress,
                toUnmatch,
                0,
                0,
                toUnmatch,
                p2pExchangeRate,
                borrowIndex
            );
            account = borrowersInP2P[_poolTokenAddress].getHead();
        }
        // Borrow on Comp
        require(poolToken.borrow(_amount - remainingToUnmatch) == 0);
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
        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            vars.poolTokenEntered = enteredMarkets[_account][i];
            vars.p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                vars.poolTokenEntered
            );
            // Calculation of the current debt (in underlying)
            vars.debtToAdd =
                borrowBalanceInOf[vars.poolTokenEntered][_account].onPool.mul(
                    ICErc20(vars.poolTokenEntered).borrowIndex()
                ) +
                borrowBalanceInOf[vars.poolTokenEntered][_account].inP2P.mul(vars.p2pExchangeRate);
            // Calculation of the current collateral (in underlying)
            vars.collateralToAdd =
                supplyBalanceInOf[vars.poolTokenEntered][_account].onPool.mul(
                    ICErc20(vars.poolTokenEntered).exchangeRateCurrent()
                ) +
                supplyBalanceInOf[vars.poolTokenEntered][_account].inP2P.mul(vars.p2pExchangeRate);
            // Price recovery
            vars.underlyingPrice = compoundOracle.getUnderlyingPrice(vars.poolTokenEntered);
            require(vars.underlyingPrice != 0, Errors.PM_ORACLE_FAIL);

            // Add the collateral value in this asset to the global collateral value (in dollars)
            (, uint256 collateralFactorMantissa, ) = comptroller.markets(vars.poolTokenEntered);
            // Conversion of the collateral to dollars
            vars.collateralToAdd = vars.collateralToAdd.mul(vars.underlyingPrice);
            // Add the max debt value allowed by the collateral in this asset to the global max debt value (in dollars)
            vars.maxDebtValue += vars.collateralToAdd.mul(collateralFactorMantissa);
            // Add the debt in this market to the global debt (in dollars)
            vars.debtValue += vars.debtToAdd.mul(vars.underlyingPrice);
            if (_poolTokenAddress == vars.poolTokenEntered) {
                vars.debtValue += _borrowedAmount.mul(vars.underlyingPrice);
                vars.maxDebtValue -= _withdrawnAmount.mul(vars.underlyingPrice).mul(
                    collateralFactorMantissa
                );
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
