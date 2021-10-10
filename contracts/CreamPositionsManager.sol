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
        uint256 onMorpho; // In mUnit (a unit that grows in value, to keep track of the debt increase).
        uint256 onComp; // In cToken.
    }

    struct BorrowBalance {
        uint256 onMorpho; // In mUnit.
        uint256 onComp; // In cdUnit. (a unit that grows in value, to keep track of the  debt increase). Multiply by current borrowIndex to get the underlying amount.
    }

    // Struct to avoid stack too deep error
    struct StateBalance {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 collateralValue; // The collateral value (in USD).
        uint256 redeemedValue; // The redeemed value if any (in USD).
    }

    // Struct to avoid stack too deep error
    struct StateBalanceVars {
        uint256 toAddDebt;
        uint256 toAddCollateral;
        uint256 mExchangeRate;
        uint256 underlyingPrice;
        address cErc20Entered;
    }

    // Struct to avoid stack too deep error
    struct LiquidateVars {
        uint256 borrowBalance;
        uint256 priceCollateralMantissa;
        uint256 priceBorrowedMantissa;
        uint256 amountToSeize;
        uint256 onCompInUnderlying;
    }

    /* Storage */

    mapping(address => RedBlackBinaryTree.Tree) public suppliersOnMorpho; // Suppliers on Morpho.
    mapping(address => RedBlackBinaryTree.Tree) public suppliersOnComp; // Suppliers on Compound.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersOnMorpho; // Borrowers on Morpho.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersOnComp; // Borrowers on Compound.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // Supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // Borrow balance of user.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;
    ICompMarketsManager public compMarketsManager;

    /* Events */

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _cErc20Address The address of the market where assets are deposited into.
     *  @param _amount The amount of assets.
     */
    event Deposited(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a redeem happens.
     *  @param _account The address of the redeemer.
     *  @param _cErc20Address The address of the market from where assets are redeemed.
     *  @param _amount The amount of assets.
     */
    event Redeemed(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _cErc20Address The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrowed(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _cErc20Address The address of the market where assets are deposited.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Morpho to Compound.
     *  @param _account The address of the supplier.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromMorphoToComp(
        address indexed _account,
        address indexed _cErc20Address,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from Compound to Morpho.
     *  @param _account The address of the supplier.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromCompToMorpho(
        address indexed _account,
        address indexed _cErc20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Morpho to Compound.
     *  @param _account The address of the borrower.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromMorphoToComp(
        address indexed _account,
        address indexed _cErc20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Compound to Morpho.
     *  @param _account The address of the borrower.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromCompToMorpho(
        address indexed _account,
        address indexed _cErc20Address,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not listed.
     *  @param _cErc20Address The address of the market.
     */
    modifier isMarketListed(address _cErc20Address) {
        require(compMarketsManager.isListed(_cErc20Address), "mkt-not-listed");
        _;
    }

    /** @dev Prevents a user to deposit or borrow less than threshold.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _cErc20Address, uint256 _amount) {
        require(_amount >= compMarketsManager.thresholds(_cErc20Address), "amount<threshold");
        _;
    }

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(compMarketsManager), "only-mkt-manager");
        _;
    }

    /* Constructor */

    constructor(ICompMarketsManager _compMarketsManager, address _proxyComptrollerAddress) {
        compMarketsManager = _compMarketsManager;
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /* External */

    /** @dev Creates Compound's markets.
     *  @param markets The address of the market the user wants to deposit.
     *  @return The results of entered.
     */
    function createMarkets(address[] memory markets)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        return comptroller.enterMarkets(markets);
    }

    /** @dev Sets the comptroller and oracle address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyMarketsManager {
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /** @dev Deposits ERC20 tokens in a specific market.
     *  @param _cErc20Address The address of the market the user wants to deposit.
     *  @param _amount The amount to deposit in ERC20 tokens.
     */
    function deposit(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cErc20Address)
        isAboveThreshold(_cErc20Address, _amount)
    {
        _handleMembership(_cErc20Address, msg.sender);
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();

        // If some borrowers are on Compound, we must move them to Morpho
        if (borrowersOnComp[_cErc20Address].isKeyInTree()) {
            uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);
            // Find borrowers and move them to Morpho
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                _cErc20Address,
                _amount
            ); // In underlying

            uint256 toRepay = _amount - remainingToSupplyToComp;
            // We must repay what we owe to Compound; the amount borrowed by the borrowers on Compound
            if (toRepay > 0) {
                supplyBalanceInOf[_cErc20Address][msg.sender].onMorpho += toRepay.div(
                    mExchangeRate
                ); // In mUnit
                erc20Token.safeApprove(_cErc20Address, toRepay);
                cErc20Token.repayBorrow(toRepay);
            }

            if (remainingToSupplyToComp > 0) {
                supplyBalanceInOf[_cErc20Address][msg.sender].onComp += remainingToSupplyToComp.div(
                    cExchangeRate
                ); // In cToken
                _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp); // Revert on error
            }
        } else {
            supplyBalanceInOf[_cErc20Address][msg.sender].onComp += _amount.div(cExchangeRate); // In cToken
            _supplyErc20ToComp(_cErc20Address, _amount); // Revert on error
        }

        _updateSupplierList(_cErc20Address, msg.sender);
        emit Deposited(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cErc20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cErc20Address)
        isAboveThreshold(_cErc20Address, _amount)
    {
        _handleMembership(_cErc20Address, msg.sender);
        _checkAccountLiquidity(msg.sender, _cErc20Address, 0, _amount);
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);

        // If some suppliers are on Compound, we must move them to Morpho
        if (suppliersOnComp[_cErc20Address].isKeyInTree()) {
            uint256 remainingToBorrowOnComp = _moveSuppliersFromCompToMorpho(
                _cErc20Address,
                _amount
            ); // In underlying
            uint256 toRedeem = _amount - remainingToBorrowOnComp;

            if (toRedeem > 0) {
                borrowBalanceInOf[_cErc20Address][msg.sender].onMorpho += toRedeem.div(
                    mExchangeRate
                ); // In mUnit
                _redeemErc20FromComp(_cErc20Address, toRedeem); // Revert on error
            }

            // If not enough cTokens on Morpho, we must borrow it on Compound
            if (remainingToBorrowOnComp > 0) {
                _moveSupplierFromMorphoToComp(msg.sender); // This must be enhanced to supply only what's required to borrow.
                require(cErc20Token.borrow(remainingToBorrowOnComp) == 0, "bor:borrow-comp-fail");
                borrowBalanceInOf[_cErc20Address][msg.sender].onComp += remainingToBorrowOnComp.div(
                    cErc20Token.borrowIndex()
                ); // In cdUnit
            }
        } else {
            // Gas intensive process below: we deconnect the supply matched on Morpho to deposit it on Compound and borrow against it
            _moveSupplierFromMorphoToComp(msg.sender);
            require(cErc20Token.borrow(_amount) == 0, "bor:borrow-comp-fail");
            borrowBalanceInOf[_cErc20Address][msg.sender].onComp += _amount.div(
                cErc20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_cErc20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cErc20Address, uint256 _amount) external nonReentrant {
        _repay(_cErc20Address, msg.sender, _amount);
    }

    /** @dev Redeems ERC20 tokens from supply.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function redeem(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cErc20Address)
    {
        require(_amount > 0, "red:amount=0");
        _checkAccountLiquidity(msg.sender, _cErc20Address, _amount, 0);
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = supplyBalanceInOf[_cErc20Address][msg.sender].onComp.mul(
            cExchangeRate
        );

        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where we can directly withdraw unused liquidity from Compound
            supplyBalanceInOf[_cErc20Address][msg.sender].onComp -= _amount.div(cExchangeRate); // In cToken
            _redeemErc20FromComp(_cErc20Address, _amount); // Revert on error
        } else {
            // First, we take all the unused liquidy on Compound.
            _redeemErc20FromComp(_cErc20Address, amountOnCompInUnderlying); // Revert on error
            supplyBalanceInOf[_cErc20Address][msg.sender].onComp -= amountOnCompInUnderlying.div(
                cExchangeRate
            );
            // Then, search for the remaining liquidity on Morpho
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying
            supplyBalanceInOf[_cErc20Address][msg.sender].onMorpho -= remainingToWithdraw.div(
                mExchangeRate
            ); // In mUnit
            uint256 cTokenContractBalanceInUnderlying = cErc20Token.balanceOf(address(this)).mul(
                cExchangeRate
            );

            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough cTokens in the contract to use
                require(
                    _moveSuppliersFromCompToMorpho(_cErc20Address, remainingToWithdraw) == 0,
                    "red:remaining-suppliers!=0"
                );
                _redeemErc20FromComp(_cErc20Address, remainingToWithdraw); // Revert on error
            } else {
                // The contract does not have enough cTokens for the withdraw
                // First, we use all the available cTokens in the contract
                uint256 toRedeem = cTokenContractBalanceInUnderlying -
                    _moveSuppliersFromCompToMorpho(
                        _cErc20Address,
                        cTokenContractBalanceInUnderlying
                    ); // The amount that can be redeemed for underlying
                // Update the remaining amount to withdraw to `msg.sender`
                remainingToWithdraw -= toRedeem;
                _redeemErc20FromComp(_cErc20Address, toRedeem); // Revert on error
                // Then, we move borrowers not matched anymore from Morpho to Compound and borrow the amount directly on Compound
                require(
                    _moveBorrowersFromMorphoToComp(_cErc20Address, remainingToWithdraw) == 0,
                    "red:remaining-borrowers!=0"
                );
                require(cErc20Token.borrow(remainingToWithdraw) == 0, "red:borrow-comp-fail");
            }
        }

        _updateSupplierList(_cErc20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Redeemed(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _cErc20BorrowedAddress The address of the debt token the liquidator wants to repay.
     *  @param _cErc20CollateralAddress The address of the collateral the liquidator wants to seize.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(
        address _cErc20BorrowedAddress,
        address _cErc20CollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalStateBalances(
            _borrower,
            address(0),
            0,
            0
        );
        require(debtValue > maxDebtValue, "liq:debt-value<=max");
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_cErc20BorrowedAddress][_borrower].onComp.mul(
                ICErc20(_cErc20BorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cErc20BorrowedAddress][_borrower].onMorpho.mul(
                compMarketsManager.mUnitExchangeRate(_cErc20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(comptroller.closeFactorMantissa()),
            "liq:amount>allowed"
        );

        _repay(_cErc20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(_cErc20CollateralAddress);
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_cErc20BorrowedAddress);
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
        ICErc20 cErc20CollateralToken = ICErc20(_cErc20CollateralAddress);
        IERC20 erc20CollateralToken = IERC20(cErc20CollateralToken.underlying());

        vars.amountToSeize = _amount
            .mul(vars.priceBorrowedMantissa)
            .mul(comptroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.onCompInUnderlying = supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onComp.mul(
            cErc20CollateralToken.exchangeRateStored()
        );
        uint256 totalCollateral = vars.onCompInUnderlying +
            supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onMorpho.mul(
                compMarketsManager.updateMUnitExchangeRate(_cErc20CollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liq:toseize>collateral");

        if (vars.amountToSeize <= vars.onCompInUnderlying) {
            // Seize tokens from Compound
            supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onComp -= vars.amountToSeize.div(
                cErc20CollateralToken.exchangeRateStored()
            );
            _redeemErc20FromComp(_cErc20CollateralAddress, vars.amountToSeize);
        } else {
            // Seize tokens from Morpho and Compound
            uint256 toMove = vars.amountToSeize - vars.onCompInUnderlying;
            supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onMorpho -= toMove.div(
                compMarketsManager.mUnitExchangeRate(_cErc20CollateralAddress)
            );

            // Check balances before and after to avoid round errors issues
            uint256 balanceBefore = erc20CollateralToken.balanceOf(address(this));
            require(
                cErc20CollateralToken.redeem(
                    supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onComp
                ) == 0,
                "liq:redeem-cToken-fail"
            );
            supplyBalanceInOf[_cErc20CollateralAddress][_borrower].onComp = 0;
            require(cErc20CollateralToken.borrow(toMove) == 0, "liq:borrow-comp-fail");
            uint256 balanceAfter = erc20CollateralToken.balanceOf(address(this));
            vars.amountToSeize = balanceAfter - balanceBefore;
            _moveBorrowersFromMorphoToComp(_cErc20CollateralAddress, toMove);
        }

        _updateSupplierList(_cErc20CollateralAddress, _borrower);
        erc20CollateralToken.safeTransfer(msg.sender, vars.amountToSeize);
    }

    /* Internal */

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrow.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _cErc20Address,
        address _borrower,
        uint256 _amount
    ) internal isMarketListed(_cErc20Address) {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);

        // If some borrowers are on Compound, we must move them to Morpho
        if (borrowBalanceInOf[_cErc20Address][_borrower].onComp > 0) {
            uint256 borrowIndex = cErc20Token.borrowIndex();
            uint256 onCompInUnderlying = borrowBalanceInOf[_cErc20Address][_borrower].onComp.mul(
                borrowIndex
            );

            // If the amount repaid is below what's on Compound, repay the borrowing amount on Compound
            if (_amount <= onCompInUnderlying) {
                borrowBalanceInOf[_cErc20Address][_borrower].onComp -= _amount.div(borrowIndex); // In cdUnit
                erc20Token.safeApprove(_cErc20Address, _amount);
                cErc20Token.repayBorrow(_amount);
            } else {
                // Else repay Compound and move the remaining liquidity to Compound
                uint256 remainingToSupplyToComp = _amount - onCompInUnderlying; // In underlying
                borrowBalanceInOf[_cErc20Address][_borrower].onMorpho -= remainingToSupplyToComp
                    .div(mExchangeRate);
                borrowBalanceInOf[_cErc20Address][_borrower].onComp -= onCompInUnderlying.div(
                    borrowIndex
                );
                require(
                    _moveSuppliersFromMorphoToComp(_cErc20Address, remainingToSupplyToComp) == 0,
                    "_rep(1):remaining-suppliers!=0"
                );
                erc20Token.safeApprove(_cErc20Address, onCompInUnderlying);
                cErc20Token.repayBorrow(onCompInUnderlying); // Revert on error

                if (remainingToSupplyToComp > 0)
                    _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp);
            }
        } else {
            borrowBalanceInOf[_cErc20Address][_borrower].onMorpho -= _amount.div(mExchangeRate); // In mUnit
            require(
                _moveSuppliersFromMorphoToComp(_cErc20Address, _amount) == 0,
                "_rep(2):remaining-suppliers!=0"
            );
            _supplyErc20ToComp(_cErc20Address, _amount);
        }

        _updateBorrowerList(_cErc20Address, _borrower);
        emit Repaid(_borrower, _cErc20Address, _amount);
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyErc20ToComp(address _cErc20Address, uint256 _amount) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeApprove(_cErc20Address, _amount);
        require(cErc20Token.mint(_amount) == 0, "_supp-to-comp:cToken-mint-fail");
    }

    /** @dev Redeems ERC20 tokens from Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be redeemed.
     */
    function _redeemErc20FromComp(address _cErc20Address, uint256 _amount) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        require(cErc20Token.redeemUnderlying(_amount) == 0, "_redeem-from-comp:redeem-comp-fail");
    }

    /** @dev Finds liquidity on Compound and moves it to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMove The remaining liquidity to search for in underlying.
     */
    function _moveSuppliersFromCompToMorpho(address _cErc20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMove = _amount; // In underlying
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 highestValue = suppliersOnComp[_cErc20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            // Loop on the keys (addresses) sharing the same value
            while (suppliersOnComp[_cErc20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnComp[_cErc20Address].valueKeyAtIndex(highestValue, 0); // Pick the first account in the list
                uint256 onComp = supplyBalanceInOf[_cErc20Address][account].onComp; // In cToken

                if (onComp > 0) {
                    uint256 toMove;
                    // This is done to prevent rounding errors
                    if (onComp.mul(cExchangeRate) <= remainingToMove) {
                        supplyBalanceInOf[_cErc20Address][account].onComp = 0;
                        toMove = onComp.mul(cExchangeRate);
                    } else {
                        toMove = remainingToMove;
                        supplyBalanceInOf[_cErc20Address][account].onComp -= toMove.div(
                            cExchangeRate
                        ); // In cToken
                    }
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_cErc20Address][account].onMorpho += toMove.div(
                        mExchangeRate
                    ); // In mUnit

                    _updateSupplierList(_cErc20Address, account);
                    emit SupplierMovedFromCompToMorpho(account, _cErc20Address, toMove);
                }
            }
            // Update the highest value after the tree has been updated
            highestValue = suppliersOnComp[_cErc20Address].last();
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to search for in underlying.
     */
    function _moveSuppliersFromMorphoToComp(address _cErc20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMove = _amount; // In underlying
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 highestValue = suppliersOnMorpho[_cErc20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (suppliersOnMorpho[_cErc20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnMorpho[_cErc20Address].valueKeyAtIndex(
                    highestValue,
                    0
                );
                uint256 onMorpho = supplyBalanceInOf[_cErc20Address][account].onMorpho; // In cToken

                if (onMorpho > 0) {
                    uint256 toMove = Math.min(onMorpho.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_cErc20Address][account].onComp += toMove.div(cExchangeRate); // In cToken
                    supplyBalanceInOf[_cErc20Address][account].onMorpho -= toMove.div(
                        mExchangeRate
                    ); // In mUnit

                    _updateSupplierList(_cErc20Address, account);
                    emit SupplierMovedFromMorphoToComp(account, _cErc20Address, toMove);
                }
            }
            highestValue = suppliersOnMorpho[_cErc20Address].last();
        }
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromMorphoToComp(address _cErc20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 highestValue = borrowersOnMorpho[_cErc20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersOnMorpho[_cErc20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnMorpho[_cErc20Address].valueKeyAtIndex(
                    highestValue,
                    0
                );
                uint256 onMorpho = borrowBalanceInOf[_cErc20Address][account].onMorpho;

                if (onMorpho > 0) {
                    uint256 toMove = Math.min(onMorpho.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_cErc20Address][account].onComp += toMove.div(borrowIndex);
                    borrowBalanceInOf[_cErc20Address][account].onMorpho -= toMove.div(
                        mExchangeRate
                    );

                    _updateBorrowerList(_cErc20Address, account);
                    emit BorrowerMovedFromMorphoToComp(account, _cErc20Address, toMove);
                }
            }
            highestValue = borrowersOnMorpho[_cErc20Address].last();
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromCompToMorpho(address _cErc20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 highestValue = borrowersOnComp[_cErc20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersOnComp[_cErc20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnComp[_cErc20Address].valueKeyAtIndex(highestValue, 0);
                uint256 onComp = borrowBalanceInOf[_cErc20Address][account].onComp; // In cToken

                if (onComp > 0) {
                    uint256 toMove;
                    if (onComp.mul(borrowIndex) <= remainingToMove) {
                        toMove = onComp.mul(borrowIndex);
                        borrowBalanceInOf[_cErc20Address][account].onComp = 0;
                    } else {
                        toMove = remainingToMove;
                        borrowBalanceInOf[_cErc20Address][account].onComp -= toMove.div(
                            borrowIndex
                        );
                    }
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_cErc20Address][account].onMorpho += toMove.div(
                        mExchangeRate
                    );

                    _updateBorrowerList(_cErc20Address, account);
                    emit BorrowerMovedFromCompToMorpho(account, _cErc20Address, toMove);
                }
            }
            highestValue = borrowersOnComp[_cErc20Address].last();
        }
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Compound.
     * @param _account The address of the account to move balance.
     */
    function _moveSupplierFromMorphoToComp(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cErc20Entered = enteredMarkets[_account][i];
            uint256 onMorpho = supplyBalanceInOf[cErc20Entered][_account].onMorpho;

            if (onMorpho > 0) {
                uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(cErc20Entered);
                uint256 cExchangeRate = ICErc20(cErc20Entered).exchangeRateCurrent();
                uint256 onMorphoInUnderlying = onMorpho.mul(mExchangeRate);
                supplyBalanceInOf[cErc20Entered][_account].onComp += onMorphoInUnderlying.div(
                    cExchangeRate
                ); // In cToken
                supplyBalanceInOf[cErc20Entered][_account].onMorpho -= onMorphoInUnderlying.div(
                    mExchangeRate
                ); // In mUnit

                _moveBorrowersFromMorphoToComp(cErc20Entered, onMorphoInUnderlying);
                _updateSupplierList(cErc20Entered, _account);
                emit SupplierMovedFromMorphoToComp(_account, cErc20Entered, onMorphoInUnderlying);
            }
        }
    }

    /**
     * @dev Updates the account membership.
     * @param _account The address of the account to update.
     * @param _cTokenAddress The address of the market to check.
     */
    function _handleMembership(address _cTokenAddress, address _account) internal {
        if (!accountMembership[_cTokenAddress][_account]) {
            accountMembership[_cTokenAddress][_account] = true;
            enteredMarkets[_account].push(_cTokenAddress);
        }
    }

    /** @dev Checks whether the user can borrow/redeem or not.
     *  @param _account The user to determine liquidity for.
     *  @param _cErc20Address The market to hypothetically redeem/borrow in.
     *  @param _redeemedAmount The number of tokens to hypothetically redeem.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     */
    function _checkAccountLiquidity(
        address _account,
        address _cErc20Address,
        uint256 _redeemedAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalStateBalances(
            _account,
            _cErc20Address,
            _redeemedAmount,
            _borrowedAmount
        );
        require(debtValue < maxDebtValue, "debt-value>max");
    }

    /** @dev Returns the debt price, max debt price and collateral price of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _cErc20Address The market to hypothetically redeem/borrow in.
     *  @param _redeemedAmount The number of tokens to hypothetically redeem.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtPrice, maxDebtPrice, collateralPrice).
     */
    function _getUserHypotheticalStateBalances(
        address _account,
        address _cErc20Address,
        uint256 _redeemedAmount,
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
        StateBalance memory stateBalance;

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            // Avoid stack too deep error
            StateBalanceVars memory vars;
            vars.cErc20Entered = enteredMarkets[_account][i];
            vars.mExchangeRate = compMarketsManager.updateMUnitExchangeRate(vars.cErc20Entered);

            vars.toAddDebt =
                borrowBalanceInOf[vars.cErc20Entered][_account].onComp.mul(
                    ICErc20(vars.cErc20Entered).borrowIndex()
                ) +
                borrowBalanceInOf[vars.cErc20Entered][_account].onMorpho.mul(vars.mExchangeRate);
            vars.toAddCollateral =
                supplyBalanceInOf[vars.cErc20Entered][_account].onComp.mul(
                    ICErc20(vars.cErc20Entered).exchangeRateCurrent()
                ) +
                supplyBalanceInOf[vars.cErc20Entered][_account].onMorpho.mul(vars.mExchangeRate);
            vars.underlyingPrice = compoundOracle.getUnderlyingPrice(vars.cErc20Entered);
            require(vars.underlyingPrice != 0, "_getUserHypotheticalStateBalances: oracle failed");

            if (_cErc20Address == vars.cErc20Entered) {
                vars.toAddDebt += _borrowedAmount;
                stateBalance.redeemedValue = _redeemedAmount.mul(vars.underlyingPrice);
            }

            vars.toAddCollateral = vars.toAddCollateral.mul(vars.underlyingPrice);
            stateBalance.debtValue += vars.toAddDebt.mul(vars.underlyingPrice);
            stateBalance.collateralValue += vars.toAddCollateral;
            (, uint256 collateralFactorMantissa, ) = comptroller.markets(vars.cErc20Entered);
            stateBalance.maxDebtValue += vars.toAddCollateral.mul(collateralFactorMantissa);
        }

        stateBalance.collateralValue -= stateBalance.redeemedValue;

        return (stateBalance.debtValue, stateBalance.maxDebtValue, stateBalance.collateralValue);
    }

    /** @dev Updates borrower lists.
     *  @param _cErc20Address The address of the market on which we want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function _updateBorrowerList(address _cErc20Address, address _account) internal {
        if (borrowersOnComp[_cErc20Address].keyExists(_account))
            borrowersOnComp[_cErc20Address].remove(_account);
        if (borrowersOnMorpho[_cErc20Address].keyExists(_account))
            borrowersOnMorpho[_cErc20Address].remove(_account);
        if (borrowBalanceInOf[_cErc20Address][_account].onComp > 0) {
            borrowersOnComp[_cErc20Address].insert(
                _account,
                borrowBalanceInOf[_cErc20Address][_account].onComp
            );
        }
        if (borrowBalanceInOf[_cErc20Address][_account].onMorpho > 0) {
            borrowersOnMorpho[_cErc20Address].insert(
                _account,
                borrowBalanceInOf[_cErc20Address][_account].onMorpho
            );
        }
    }

    /** @dev Updates supplier lists.
     *  @param _cErc20Address The address of the market on which we want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function _updateSupplierList(address _cErc20Address, address _account) internal {
        if (suppliersOnComp[_cErc20Address].keyExists(_account))
            suppliersOnComp[_cErc20Address].remove(_account);
        if (suppliersOnMorpho[_cErc20Address].keyExists(_account))
            suppliersOnMorpho[_cErc20Address].remove(_account);
        if (supplyBalanceInOf[_cErc20Address][_account].onComp > 0) {
            suppliersOnComp[_cErc20Address].insert(
                _account,
                supplyBalanceInOf[_cErc20Address][_account].onComp
            );
        }
        if (supplyBalanceInOf[_cErc20Address][_account].onMorpho > 0) {
            suppliersOnMorpho[_cErc20Address].insert(
                _account,
                supplyBalanceInOf[_cErc20Address][_account].onMorpho
            );
        }
    }
}
