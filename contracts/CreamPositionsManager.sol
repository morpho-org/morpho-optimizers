// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import "./libraries/RedBlackBinaryTree.sol";
import "./interfaces/ICompMarketsManager.sol";
import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CreamPositionsManager
 *  @dev Smart contracts interacting with Cream to enable real P2P supply with cERC20 tokens as supply/borrow assets.
 */
contract CreamPositionsManager is ReentrancyGuard {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In mUnit (a unit that grows in value, to keep track of the debt increase).
        uint256 onCream; // In crToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In mUnit.
        uint256 onCream; // In cdUnit. (a unit that grows in value, to keep track of the  debt increase). Multiply by current borrowIndex to get the underlying amount.
    }

    // Struct to avoid stack too deep error
    struct BalanceStateVars {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 redeemedValue; // The redeemed value if any (in USD).
        uint256 collateralValue; // The collateral value (in USD).
        uint256 debtToAdd; // The debt to add at the current iteration.
        uint256 collateralToAdd; // The collateral to add at the current iteration.
        address cERC20Entered; // The cERC20 token entered by the user.
        uint256 mExchangeRate; // The mUnit exchange rate of the `cErc20Entered`.
        uint256 underlyingPrice; // The price of the underlying linked to the `cErc20Entered`.
    }

    // Struct to avoid stack too deep error
    struct LiquidateVars {
        uint256 borrowBalance;
        uint256 priceCollateralMantissa;
        uint256 priceBorrowedMantissa;
        uint256 amountToSeize;
        uint256 onCreamInUnderlying;
    }

    /* Storage */

    mapping(address => RedBlackBinaryTree.Tree) public suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) public suppliersOnCream; // Suppliers on Cream.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersOnCream; // Borrowers on Cream.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.

    IComptroller public creamtroller;
    ICompoundOracle public creamOracle;
    ICompMarketsManager public creamMarketsManager;

    /* Events */

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _crERC20Address The address of the market where assets are deposited into.
     *  @param _amount The amount of assets.
     */
    event Deposited(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a withdraw happens.
     *  @param _account The address of the withdrawer.
     *  @param _crERC20Address The address of the market from where assets are withdrawn.
     *  @param _amount The amount of assets.
     */
    event Withdrawn(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _crERC20Address The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrowed(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _crERC20Address The address of the market where assets are deposited.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Morpho to Cream.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromMorphoToCream(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from Cream to Morpho.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromCreamToMorpho(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Morpho to Cream.
     *  @param _account The address of the borrower.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromMorphoToCream(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Cream to Morpho.
     *  @param _account The address of the borrower.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromCreamToMorpho(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not listed.
     *  @param _crERC20Address The address of the market.
     */
    modifier isMarketListed(address _crERC20Address) {
        require(creamMarketsManager.isListed(_crERC20Address), "mkt-not-listed");
        _;
    }

    /** @dev Prevents a user to deposit or borrow less than threshold.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _crERC20Address, uint256 _amount) {
        require(_amount >= creamMarketsManager.thresholds(_crERC20Address), "amount<threshold");
        _;
    }

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(creamMarketsManager), "only-mkt-manager");
        _;
    }

    /* Constructor */

    constructor(ICompMarketsManager _creamMarketsManager, address _proxyCreamtrollerAddress) {
        creamMarketsManager = _creamMarketsManager;
        creamtroller = IComptroller(_proxyCreamtrollerAddress);
        creamOracle = ICompoundOracle(creamtroller.oracle());
    }

    /* External */

    /** @dev Creates Cream's markets.
     *  @param markets The address of the market the user wants to deposit.
     *  @return The results of entered.
     */
    function createMarkets(address[] calldata markets)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        return creamtroller.enterMarkets(markets);
    }

    /** @dev Sets the comptroller and oracle address.
     *  @param _proxyCreamtrollerAddress The address of Cream's creamtroller.
     */
    function setComptroller(address _proxyCreamtrollerAddress) external onlyMarketsManager {
        creamtroller = IComptroller(_proxyCreamtrollerAddress);
        creamOracle = ICompoundOracle(creamtroller.oracle());
    }

    /** @dev Deposits ERC20 tokens in a specific market.
     *  @param _crERC20Address The address of the market the user wants to deposit.
     *  @param _amount The amount to deposit in ERC20 tokens.
     */
    function deposit(address _crERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_crERC20Address)
        isAboveThreshold(_crERC20Address, _amount)
    {
        _handleMembership(_crERC20Address, msg.sender);
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = crERC20Token.exchangeRateCurrent();

        /* SCENARIO 1: Waiting borrowers -> match in P2P */
        if (borrowersOnCream[_crERC20Address].isNotEmpty()) {
            uint256 mExchangeRate = creamMarketsManager.updateMUnitExchangeRate(_crERC20Address);
            uint256 remainingToSupplyToCream = _moveBorrowersFromCreamToP2P(
                _crERC20Address,
                _amount
            ); // In underlying
            uint256 toRepay = _amount - remainingToSupplyToCream;
            if (toRepay > 0) {
                supplyBalanceInOf[_crERC20Address][msg.sender].inP2P += toRepay.div(mExchangeRate); // In mUnit
                erc20Token.safeApprove(_crERC20Address, toRepay);
                crERC20Token.repayBorrow(toRepay);
            }
            /* SCENARIO 1.1: Not enough waiting borrowers -> supply the remaining to Cream */
            if (remainingToSupplyToCream > 0) {
                supplyBalanceInOf[_crERC20Address][msg.sender].onCream += remainingToSupplyToCream
                    .div(cExchangeRate); // In crToken
                _supplyERC20ToCream(_crERC20Address, remainingToSupplyToCream); // Revert on error
            }
        }
        /* SCENARIO 2: No waiting borrowers -> supply to Cream */
        else {
            supplyBalanceInOf[_crERC20Address][msg.sender].onCream += _amount.div(cExchangeRate); // In crToken
            _supplyERC20ToCream(_crERC20Address, _amount); // Revert on error
        }

        _updateSupplierList(_crERC20Address, msg.sender);
        emit Deposited(msg.sender, _crERC20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _crERC20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _crERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_crERC20Address)
        isAboveThreshold(_crERC20Address, _amount)
    {
        _handleMembership(_crERC20Address, msg.sender);
        _checkAccountLiquidity(msg.sender, _crERC20Address, 0, _amount);
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);

        /* SCENARIO 1: Waiting suppliers -> match in P2P */
        if (suppliersOnCream[_crERC20Address].isNotEmpty()) {
            uint256 remainingToBorrowOnCream = _moveSuppliersFromCreamToP2P(
                _crERC20Address,
                _amount
            ); // In underlying
            uint256 toWithdraw = _amount - remainingToBorrowOnCream;

            if (toWithdraw > 0) {
                borrowBalanceInOf[_crERC20Address][msg.sender].inP2P += toWithdraw.div(
                    mExchangeRate
                ); // In mUnit
                _withdrawERC20FromCream(_crERC20Address, toWithdraw); // Revert on error
            }

            /* SCENARIO 1.1: Not enough waiting supply -> borrow the rest on Cream */
            if (remainingToBorrowOnCream > 0) {
                _moveSupplierFromP2PToCream(msg.sender);
                require(
                    crERC20Token.borrow(remainingToBorrowOnCream) == 0,
                    "bor:borrow-cream-fail"
                );
                borrowBalanceInOf[_crERC20Address][msg.sender].onCream += remainingToBorrowOnCream
                    .div(crERC20Token.borrowIndex()); // In cdUnit
            }
        }
        /* SCENARIO 2: no waiting suppliers -> borrow on Cream */
        else {
            _moveSupplierFromP2PToCream(msg.sender);
            require(crERC20Token.borrow(_amount) == 0, "bor:borrow-cream-fail");
            borrowBalanceInOf[_crERC20Address][msg.sender].onCream += _amount.div(
                crERC20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_crERC20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _crERC20Address, _amount);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _crERC20Address, uint256 _amount) external nonReentrant {
        _repay(_crERC20Address, msg.sender, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _crERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_crERC20Address)
    {
        require(_amount > 0, "red:amount=0");
        _checkAccountLiquidity(msg.sender, _crERC20Address, _amount, 0);
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);
        uint256 cExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 amountOnCreamInUnderlying = supplyBalanceInOf[_crERC20Address][msg.sender]
            .onCream
            .mul(cExchangeRate);

        /* SCENARIO 1: Enough waiting supply -> withdraw it from Cream */
        if (_amount <= amountOnCreamInUnderlying) {
            supplyBalanceInOf[_crERC20Address][msg.sender].onCream -= _amount.div(cExchangeRate); // In crToken
            _withdrawERC20FromCream(_crERC20Address, _amount); // Revert on error
        }
        /* SCENARIO 2: Not Enough waiting supply */
        else {
            _withdrawERC20FromCream(_crERC20Address, amountOnCreamInUnderlying); // Revert on error
            supplyBalanceInOf[_crERC20Address][msg.sender].onCream -= amountOnCreamInUnderlying.div(
                cExchangeRate
            );
            // Then, search for the remaining liquidity in peer-to-peer
            uint256 remainingToWithdraw = _amount - amountOnCreamInUnderlying; // In underlying
            supplyBalanceInOf[_crERC20Address][msg.sender].inP2P -= remainingToWithdraw.div(
                mExchangeRate
            ); // In mUnit
            uint256 crTokenContractBalanceInUnderlying = crERC20Token.balanceOf(address(this)).mul(
                cExchangeRate
            );

            /* SCENARIO 2.1: Enough waiting suppliers -> match them with borrowers */
            if (remainingToWithdraw <= crTokenContractBalanceInUnderlying) {
                require(
                    _moveSuppliersFromCreamToP2P(_crERC20Address, remainingToWithdraw) == 0,
                    "red:remaining-suppliers!=0"
                );
                _withdrawERC20FromCream(_crERC20Address, remainingToWithdraw); // Revert on error
            }
            /* SCENARIO 2.2: Not enough waiting suppliers -> borrow on Cream */
            else {
                uint256 toWithdraw = crTokenContractBalanceInUnderlying -
                    _moveSuppliersFromCreamToP2P(
                        _crERC20Address,
                        crTokenContractBalanceInUnderlying
                    ); // The amount that can be withdrawn for underlying
                // Update the remaining amount to withdraw to `msg.sender`
                remainingToWithdraw -= toWithdraw;
                _withdrawERC20FromCream(_crERC20Address, toWithdraw); // Revert on error
                require(
                    _moveBorrowersFromP2PToCream(_crERC20Address, remainingToWithdraw) == 0,
                    "red:remaining-borrowers!=0"
                );
                require(crERC20Token.borrow(remainingToWithdraw) == 0, "red:borrow-cream-fail");
            }
        }

        _updateSupplierList(_crERC20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _crERC20Address, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _cERC20BorrowedAddress The address of the debt token the liquidator wants to repay.
     *  @param _cERC20CollateralAddress The address of the collateral the liquidator wants to seize.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(
        address _cERC20BorrowedAddress,
        address _cERC20CollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        require(debtValue > maxDebtValue, "liq:debt-value<=max");
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].onCream.mul(
                ICErc20(_cERC20BorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].inP2P.mul(
                creamMarketsManager.mUnitExchangeRate(_cERC20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(creamtroller.closeFactorMantissa()),
            "liq:amount>allowed"
        );

        _repay(_cERC20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = creamOracle.getUnderlyingPrice(_cERC20CollateralAddress);
        vars.priceBorrowedMantissa = creamOracle.getUnderlyingPrice(_cERC20BorrowedAddress);
        require(
            vars.priceCollateralMantissa != 0 && vars.priceBorrowedMantissa != 0,
            "liq:oracle-fail"
        );

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        ICErc20 cERC20CollateralToken = ICErc20(_cERC20CollateralAddress);
        IERC20 erc20CollateralToken = IERC20(cERC20CollateralToken.underlying());

        vars.amountToSeize = _amount
            .mul(vars.priceBorrowedMantissa)
            .mul(creamtroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.onCreamInUnderlying = supplyBalanceInOf[_cERC20CollateralAddress][_borrower]
            .onCream
            .mul(cERC20CollateralToken.exchangeRateStored());
        uint256 totalCollateral = vars.onCreamInUnderlying +
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P.mul(
                creamMarketsManager.updateMUnitExchangeRate(_cERC20CollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liq:toseize>collateral");

        if (vars.amountToSeize <= vars.onCreamInUnderlying) {
            // Seize tokens from Cream
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onCream -= vars
                .amountToSeize
                .div(cERC20CollateralToken.exchangeRateStored());
            _withdrawERC20FromCream(_cERC20CollateralAddress, vars.amountToSeize);
        } else {
            // Seize tokens from Morpho and Cream
            uint256 toMove = vars.amountToSeize - vars.onCreamInUnderlying;
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P -= toMove.div(
                creamMarketsManager.mUnitExchangeRate(_cERC20CollateralAddress)
            );

            // Check balances before and after to avoid round errors issues
            uint256 balanceBefore = erc20CollateralToken.balanceOf(address(this));
            require(
                cERC20CollateralToken.redeem(
                    supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onCream
                ) == 0,
                "liq:withdraw-crToken-fail"
            );
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onCream = 0;
            require(cERC20CollateralToken.borrow(toMove) == 0, "liq:borrow-cream-fail");
            uint256 balanceAfter = erc20CollateralToken.balanceOf(address(this));
            vars.amountToSeize = balanceAfter - balanceBefore;
            _moveBorrowersFromP2PToCream(_cERC20CollateralAddress, toMove);
        }

        _updateSupplierList(_cERC20CollateralAddress, _borrower);
        erc20CollateralToken.safeTransfer(msg.sender, vars.amountToSeize);
    }

    /* Internal */

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrow.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _crERC20Address,
        address _borrower,
        uint256 _amount
    ) internal isMarketListed(_crERC20Address) {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = creamMarketsManager.updateMUnitExchangeRate(_crERC20Address);

        /* SCENARIO 1: Waiting borrowers -> match them in P2P */
        if (borrowBalanceInOf[_crERC20Address][_borrower].onCream > 0) {
            uint256 borrowIndex = crERC20Token.borrowIndex();
            uint256 onCreamInUnderlying = borrowBalanceInOf[_crERC20Address][_borrower].onCream.mul(
                borrowIndex
            );

            /* SCENARIO 1.1: Enough waiting borrowers -> repay Cream */
            if (_amount <= onCreamInUnderlying) {
                borrowBalanceInOf[_crERC20Address][_borrower].onCream -= _amount.div(borrowIndex); // In cdUnit
                erc20Token.safeApprove(_crERC20Address, _amount);
                crERC20Token.repayBorrow(_amount);
            }
            /* SCENARIO 1.2: Not Enough waiting borrowers -> unmatch suppliers */
            else {
                uint256 remainingToSupplyToCream = _amount - onCreamInUnderlying; // In underlying
                borrowBalanceInOf[_crERC20Address][_borrower].inP2P -= remainingToSupplyToCream.div(
                    mExchangeRate
                );
                borrowBalanceInOf[_crERC20Address][_borrower].onCream -= onCreamInUnderlying.div(
                    borrowIndex
                );
                require(
                    _moveSuppliersFromP2PToCream(_crERC20Address, remainingToSupplyToCream) == 0,
                    "_rep(1):remaining-suppliers!=0"
                );
                erc20Token.safeApprove(_crERC20Address, onCreamInUnderlying);
                crERC20Token.repayBorrow(onCreamInUnderlying); // Revert on error

                if (remainingToSupplyToCream > 0)
                    _supplyERC20ToCream(_crERC20Address, remainingToSupplyToCream);
            }
        }
        /* SCENARIO 2: No waiting borrowers -> supply to Cream */
        else {
            borrowBalanceInOf[_crERC20Address][_borrower].inP2P -= _amount.div(mExchangeRate); // In mUnit
            require(
                _moveSuppliersFromP2PToCream(_crERC20Address, _amount) == 0,
                "_rep(2):remaining-suppliers!=0"
            );
            _supplyERC20ToCream(_crERC20Address, _amount);
        }

        _updateBorrowerList(_crERC20Address, _borrower);
        emit Repaid(_borrower, _crERC20Address, _amount);
    }

    /** @dev Supplies ERC20 tokens to Cream.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyERC20ToCream(address _crERC20Address, uint256 _amount) internal {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeApprove(_crERC20Address, _amount);
        require(crERC20Token.mint(_amount) == 0, "_supp-to-cream:crToken-mint-fail");
    }

    /** @dev Withdraws ERC20 tokens from Cream.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromCream(address _crERC20Address, uint256 _amount) internal {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        require(
            crERC20Token.redeemUnderlying(_amount) == 0,
            "_redeem-from-cream:redeem-cream-fail"
        );
    }

    /** @dev Finds liquidity on Cream and moves it to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMove The remaining liquidity to search for in underlying.
     */
    function _moveSuppliersFromCreamToP2P(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToMove = _amount; // In underlying
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);
        uint256 cExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 highestValue = suppliersOnCream[_crERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            // Loop on the keys (addresses) sharing the same value
            while (suppliersOnCream[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnCream[_crERC20Address].valueKeyAtIndex(
                    highestValue,
                    0
                ); // Pick the first account in the list
                uint256 onCream = supplyBalanceInOf[_crERC20Address][account].onCream; // In crToken

                if (onCream > 0) {
                    uint256 toMove;
                    // This is done to prevent rounding errors
                    if (onCream.mul(cExchangeRate) <= remainingToMove) {
                        supplyBalanceInOf[_crERC20Address][account].onCream = 0;
                        toMove = onCream.mul(cExchangeRate);
                    } else {
                        toMove = remainingToMove;
                        supplyBalanceInOf[_crERC20Address][account].onCream -= toMove.div(
                            cExchangeRate
                        ); // In crToken
                    }
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_crERC20Address][account].inP2P += toMove.div(mExchangeRate); // In mUnit

                    _updateSupplierList(_crERC20Address, account);
                    emit SupplierMovedFromCreamToMorpho(account, _crERC20Address, toMove);
                }
            }
            // Update the highest value after the tree has been updated
            highestValue = suppliersOnCream[_crERC20Address].last();
        }
    }

    /** @dev Finds liquidity in peer-to-peer and moves it to Cream.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     */
    function _moveSuppliersFromP2PToCream(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToMove = _amount; // In underlying
        uint256 cExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);
        uint256 highestValue = suppliersInP2P[_crERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (suppliersInP2P[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersInP2P[_crERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = supplyBalanceInOf[_crERC20Address][account].inP2P; // In crToken

                if (inP2P > 0) {
                    uint256 toMove = Math.min(inP2P.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_crERC20Address][account].onCream += toMove.div(
                        cExchangeRate
                    ); // In crToken
                    supplyBalanceInOf[_crERC20Address][account].inP2P -= toMove.div(mExchangeRate); // In mUnit

                    _updateSupplierList(_crERC20Address, account);
                    emit SupplierMovedFromMorphoToCream(account, _crERC20Address, toMove);
                }
            }
            highestValue = suppliersInP2P[_crERC20Address].last();
        }
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and moves them to Cream.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromP2PToCream(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);
        uint256 borrowIndex = crERC20Token.borrowIndex();
        uint256 highestValue = borrowersInP2P[_crERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersInP2P[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersInP2P[_crERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = borrowBalanceInOf[_crERC20Address][account].inP2P;
                // Put all its supply on Cream
                _moveSupplierFromP2PToCream(account);
                if (inP2P > 0) {
                    uint256 toMove = Math.min(inP2P.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_crERC20Address][account].onCream += toMove.div(borrowIndex);
                    borrowBalanceInOf[_crERC20Address][account].inP2P -= toMove.div(mExchangeRate);

                    _updateBorrowerList(_crERC20Address, account);
                    emit BorrowerMovedFromMorphoToCream(account, _crERC20Address, toMove);
                }
            }
            highestValue = borrowersInP2P[_crERC20Address].last();
        }
    }

    /** @dev Finds borrowers on Cream that match the given `_amount` and moves them to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromCreamToP2P(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(_crERC20Address);
        uint256 borrowIndex = crERC20Token.borrowIndex();
        uint256 highestValue = borrowersOnCream[_crERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersOnCream[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnCream[_crERC20Address].valueKeyAtIndex(
                    highestValue,
                    0
                );
                uint256 onCream = borrowBalanceInOf[_crERC20Address][account].onCream; // In crToken

                if (onCream > 0) {
                    uint256 toMove;
                    if (onCream.mul(borrowIndex) <= remainingToMove) {
                        toMove = onCream.mul(borrowIndex);
                        borrowBalanceInOf[_crERC20Address][account].onCream = 0;
                    } else {
                        toMove = remainingToMove;
                        borrowBalanceInOf[_crERC20Address][account].onCream -= toMove.div(
                            borrowIndex
                        );
                    }
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_crERC20Address][account].inP2P += toMove.div(mExchangeRate);

                    _updateBorrowerList(_crERC20Address, account);
                    emit BorrowerMovedFromCreamToMorpho(account, _crERC20Address, toMove);
                }
            }
            highestValue = borrowersOnCream[_crERC20Address].last();
        }
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Cream.
     * @param _account The address of the account to move balance.
     */
    function _moveSupplierFromP2PToCream(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cERC20Entered = enteredMarkets[_account][i];
            uint256 inP2P = supplyBalanceInOf[cERC20Entered][_account].inP2P;

            if (inP2P > 0) {
                uint256 mExchangeRate = creamMarketsManager.mUnitExchangeRate(cERC20Entered);
                uint256 cExchangeRate = ICErc20(cERC20Entered).exchangeRateCurrent();
                uint256 inP2PInUnderlying = inP2P.mul(mExchangeRate);
                supplyBalanceInOf[cERC20Entered][_account].onCream += inP2PInUnderlying.div(
                    cExchangeRate
                ); // In crToken
                supplyBalanceInOf[cERC20Entered][_account].inP2P -= inP2PInUnderlying.div(
                    mExchangeRate
                ); // In mUnit

                _moveBorrowersFromP2PToCream(cERC20Entered, inP2PInUnderlying);
                _updateSupplierList(cERC20Entered, _account);
                emit SupplierMovedFromMorphoToCream(_account, cERC20Entered, inP2PInUnderlying);
            }
        }
    }

    /**
     * @dev Enters the user into the market if he is not already there.
     * @param _account The address of the account to update.
     * @param _crTokenAddress The address of the market to check.
     */
    function _handleMembership(address _crTokenAddress, address _account) internal {
        if (!accountMembership[_crTokenAddress][_account]) {
            accountMembership[_crTokenAddress][_account] = true;
            enteredMarkets[_account].push(_crTokenAddress);
        }
    }

    /** @dev Checks whether the user can borrow/withdraw or not.
     *  @param _account The user to determine liquidity for.
     *  @param _crERC20Address The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     */
    function _checkAccountLiquidity(
        address _account,
        address _crERC20Address,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _account,
            _crERC20Address,
            _withdrawnAmount,
            _borrowedAmount
        );
        require(debtValue < maxDebtValue, "debt-value>max");
    }

    /** @dev Returns the debt value, max debt value and collateral value of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _crERC20Address The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtValue, maxDebtValue collateralValue).
     */
    function _getUserHypotheticalBalanceStates(
        address _account,
        address _crERC20Address,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Avoid stack too deep error
        BalanceStateVars memory balanceState;

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            // Avoid stack too deep error
            BalanceStateVars memory vars;
            vars.cERC20Entered = enteredMarkets[_account][i];
            vars.mExchangeRate = creamMarketsManager.updateMUnitExchangeRate(vars.cERC20Entered);
            // Calculation of the current debt (in underlying)
            vars.debtToAdd =
                borrowBalanceInOf[vars.cERC20Entered][_account].onCream.mul(
                    ICErc20(vars.cERC20Entered).borrowIndex()
                ) +
                borrowBalanceInOf[vars.cERC20Entered][_account].inP2P.mul(vars.mExchangeRate);
            // Calculation of the current collateral (in underlying)
            vars.collateralToAdd =
                supplyBalanceInOf[vars.cERC20Entered][_account].onCream.mul(
                    ICErc20(vars.cERC20Entered).exchangeRateCurrent()
                ) +
                supplyBalanceInOf[vars.cERC20Entered][_account].inP2P.mul(vars.mExchangeRate);
            // Price recovery
            vars.underlyingPrice = creamOracle.getUnderlyingPrice(vars.cERC20Entered);
            require(vars.underlyingPrice != 0, "_getUserHypotheticalBalanceStates: oracle failed");

            if (_crERC20Address == vars.cERC20Entered) {
                vars.debtToAdd += _borrowedAmount;
                balanceState.redeemedValue = _withdrawnAmount.mul(vars.underlyingPrice);
            }
            // Conversion of the collateral to dollars
            vars.collateralToAdd = vars.collateralToAdd.mul(vars.underlyingPrice);
            // Add the debt in this market to the global debt (in dollars)
            balanceState.debtValue += vars.debtToAdd.mul(vars.underlyingPrice);
            // Add the collateral value in this asset to the global collateral value (in dollars)
            balanceState.collateralValue += vars.collateralToAdd;
            (, uint256 collateralFactorMantissa, ) = creamtroller.markets(vars.cERC20Entered);
            // Add the max debt value allowed by the collateral in this asset to the global max debt value (in dollars)
            balanceState.maxDebtValue += vars.collateralToAdd.mul(collateralFactorMantissa);
        }

        balanceState.collateralValue -= balanceState.redeemedValue;

        return (balanceState.debtValue, balanceState.maxDebtValue, balanceState.collateralValue);
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _crERC20Address The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function _updateBorrowerList(address _crERC20Address, address _account) internal {
        if (borrowersOnCream[_crERC20Address].keyExists(_account))
            borrowersOnCream[_crERC20Address].remove(_account);
        if (borrowersInP2P[_crERC20Address].keyExists(_account))
            borrowersInP2P[_crERC20Address].remove(_account);
        if (borrowBalanceInOf[_crERC20Address][_account].onCream > 0) {
            borrowersOnCream[_crERC20Address].insert(
                _account,
                borrowBalanceInOf[_crERC20Address][_account].onCream
            );
        }
        if (borrowBalanceInOf[_crERC20Address][_account].inP2P > 0) {
            borrowersInP2P[_crERC20Address].insert(
                _account,
                borrowBalanceInOf[_crERC20Address][_account].inP2P
            );
        }
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _crERC20Address The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function _updateSupplierList(address _crERC20Address, address _account) internal {
        if (suppliersOnCream[_crERC20Address].keyExists(_account))
            suppliersOnCream[_crERC20Address].remove(_account);
        if (suppliersInP2P[_crERC20Address].keyExists(_account))
            suppliersInP2P[_crERC20Address].remove(_account);
        if (supplyBalanceInOf[_crERC20Address][_account].onCream > 0) {
            suppliersOnCream[_crERC20Address].insert(
                _account,
                supplyBalanceInOf[_crERC20Address][_account].onCream
            );
        }
        if (supplyBalanceInOf[_crERC20Address][_account].inP2P > 0) {
            suppliersInP2P[_crERC20Address].insert(
                _account,
                supplyBalanceInOf[_crERC20Address][_account].inP2P
            );
        }
    }
}
