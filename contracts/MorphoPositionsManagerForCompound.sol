// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import "./libraries/RedBlackBinaryTree.sol";
import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

/**
 *  @title MorphoPositionsManagerForCompound
 *  @dev Smart contract interacting with Compound to enable P2P supply/borrow positions that can fallback on Compound's pool using cERC20 tokens.
 */
contract MorphoPositionsManagerForCompound is ReentrancyGuard {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In mUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onComp; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In mUnit.
        uint256 onComp; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Compound. Multiply by current borrowIndex to get the underlying amount.
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
        uint256 borrowBalance; // Total borrow balance of the user in underlying for a given asset.
        uint256 amountToSeize; // The amount of collateral underlying the liquidator can seize.
        uint256 priceBorrowedMantissa; // The price of the asset borrowed (in USD).
        uint256 priceCollateralMantissa; // The price of the collateral asset (in USD).
        uint256 collateralOnCompInUnderlying; // The amount of underlying the liquidatee has on Compound.
    }

    /* Storage */

    mapping(address => RedBlackBinaryTree.Tree) private suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private suppliersOnComp; // Suppliers on Compound.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersOnComp; // Borrowers on Compound.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public thresholds; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;
    IMarketsManagerForCompLike public marketsManagerForCompLike;

    /* Events */

    /** @dev Emitted when a supply happens.
     *  @param _account The address of the supplier.
     *  @param _cERC20Address The address of the market where assets are supplied into.
     *  @param _amount The amount of assets.
     */
    event Supplied(address indexed _account, address indexed _cERC20Address, uint256 _amount);

    /** @dev Emitted when a withdraw happens.
     *  @param _account The address of the withdrawer.
     *  @param _cERC20Address The address of the market from where assets are withdrawn.
     *  @param _amount The amount of assets.
     */
    event Withdrawn(address indexed _account, address indexed _cERC20Address, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _cERC20Address The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrowed(address indexed _account, address indexed _cERC20Address, uint256 _amount);

    /** @dev Emitted when a repay happens.
     *  @param _account The address of the repayer.
     *  @param _cERC20Address The address of the market where assets are repaid.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _cERC20Address, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Compound to P2P.
     *  @param _account The address of the supplier.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMatched(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from P2P to Compound.
     *  @param _account The address of the supplier.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierUnmatched(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Compound to P2P.
     *  @param _account The address of the borrower.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMatched(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from P2P to Compound.
     *  @param _account The address of the borrower.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerUnmatched(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not created yet.
     *  @param _cERC20Address The address of the market.
     */
    modifier isMarketCreated(address _cERC20Address) {
        require(marketsManagerForCompLike.isCreated(_cERC20Address), "mkt-not-created");
        _;
    }

    /** @dev Prevents a user to supply or borrow less than threshold.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _cERC20Address, uint256 _amount) {
        require(_amount >= thresholds[_cERC20Address], "amount<threshold");
        _;
    }

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(marketsManagerForCompLike), "only-mkt-manager");
        _;
    }

    /* Constructor */

    constructor(address _compoundMarketsManager, address _proxyComptrollerAddress) {
        marketsManagerForCompLike = IMarketsManagerForCompLike(_compoundMarketsManager);
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /* External */

    /** @dev Creates Compound's markets.
     *  @param _cERC20Address The address of the market the user wants to supply.
     *  @return The results of entered.
     */
    function createMarket(address _cERC20Address)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _cERC20Address;
        return comptroller.enterMarkets(marketToEnter);
    }

    /** @dev Sets the comptroller and oracle address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyMarketsManager {
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /** @dev Sets the threshold of a market.
     *  @param _cERC20Address The address of the market to set the threshold.
     *  @param _newThreshold The new threshold.
     */
    function setThreshold(address _cERC20Address, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        thresholds[_cERC20Address] = _newThreshold;
    }

    /** @dev Supplies ERC20 tokens in a specific market.
     *  @param _cERC20Address The address of the market the user wants to supply.
     *  @param _amount The amount to supply in ERC20 tokens.
     */
    function supply(address _cERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_cERC20Address)
        isAboveThreshold(_cERC20Address, _amount)
    {
        _handleMembership(_cERC20Address, msg.sender);
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();

        /* CASE 1: Some borrowers are waiting on Compound, Morpho matches the supplier in P2P with them */
        if (borrowersOnComp[_cERC20Address].isNotEmpty()) {
            uint256 mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                _cERC20Address
            );
            uint256 remainingToSupplyToComp = _matchBorrowers(_cERC20Address, _amount); // In underlying
            uint256 matched = _amount - remainingToSupplyToComp;
            if (matched > 0) {
                supplyBalanceInOf[_cERC20Address][msg.sender].inP2P += matched.div(mExchangeRate); // In mUnit
            }
            /* If there aren't enough borrowers waiting on Compound to match all the tokens supplied, the rest is supplied to Compound */
            if (remainingToSupplyToComp > 0) {
                supplyBalanceInOf[_cERC20Address][msg.sender].onComp += remainingToSupplyToComp.div(
                    cExchangeRate
                ); // In cToken
                _supplyERC20ToComp(_cERC20Address, remainingToSupplyToComp); // Revert on error
            }
        }
        /* CASE 2: There aren't any borrowers waiting on Compound, Morpho supplies all the tokens to Compound */
        else {
            supplyBalanceInOf[_cERC20Address][msg.sender].onComp += _amount.div(cExchangeRate); // In cToken
            _supplyERC20ToComp(_cERC20Address, _amount); // Revert on error
        }

        _updateSupplierList(_cERC20Address, msg.sender);
        emit Supplied(msg.sender, _cERC20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cERC20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_cERC20Address)
        isAboveThreshold(_cERC20Address, _amount)
    {
        _handleMembership(_cERC20Address, msg.sender);
        _checkAccountLiquidity(msg.sender, _cERC20Address, 0, _amount);
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);

        /* CASE 1: Some suppliers are waiting on Compound, Morpho matches the borrower in P2P with them */
        if (suppliersOnComp[_cERC20Address].isNotEmpty()) {
            uint256 remainingToBorrowOnComp = _matchSuppliers(_cERC20Address, _amount); // In underlying
            uint256 matched = _amount - remainingToBorrowOnComp;

            if (matched > 0) {
                borrowBalanceInOf[_cERC20Address][msg.sender].inP2P += matched.div(mExchangeRate); // In mUnit
            }

            /* If there aren't enough suppliers waiting on Compound to match all the tokens borrowed, the rest is borrowed from Compound */
            if (remainingToBorrowOnComp > 0) {
                _unmatchTheSupplier(msg.sender); // Before borrowing on Compound, we put all the collateral of the borrower on Compound (cf Liquidation Invariant in docs)
                require(
                    cERC20Token.borrow(remainingToBorrowOnComp) == 0,
                    "borrow(1):borrow-compound-fail"
                );
                borrowBalanceInOf[_cERC20Address][msg.sender].onComp += remainingToBorrowOnComp.div(
                    cERC20Token.borrowIndex()
                ); // In cdUnit
            }
        }
        /* CASE 2: There aren't any borrowers waiting on Compound, Morpho borrows all the tokens from Compound */
        else {
            _unmatchTheSupplier(msg.sender); // Before borrowing on Compound, we put all the collateral of the borrower on Compound (cf Liquidation Invariant in docs)
            require(cERC20Token.borrow(_amount) == 0, "borrow(2):borrow-compound-fail");
            borrowBalanceInOf[_cERC20Address][msg.sender].onComp += _amount.div(
                cERC20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_cERC20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _cERC20Address, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _cERC20Address, uint256 _amount) external nonReentrant {
        _withdraw(_cERC20Address, _amount, msg.sender, msg.sender);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cERC20Address, uint256 _amount) external nonReentrant {
        _repay(_cERC20Address, msg.sender, _amount);
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
        require(debtValue > maxDebtValue, "liquidate:debt-value<=max");
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].onComp.mul(
                ICErc20(_cERC20BorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].inP2P.mul(
                marketsManagerForCompLike.mUnitExchangeRate(_cERC20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(comptroller.closeFactorMantissa()),
            "liquidate:amount>allowed"
        );

        _repay(_cERC20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(_cERC20CollateralAddress);
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_cERC20BorrowedAddress);
        require(
            vars.priceCollateralMantissa != 0 && vars.priceBorrowedMantissa != 0,
            "liquidate:oracle-fail"
        );

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        ICErc20 cERC20CollateralToken = ICErc20(_cERC20CollateralAddress);

        vars.amountToSeize = _amount
            .mul(vars.priceBorrowedMantissa)
            .mul(comptroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.collateralOnCompInUnderlying = supplyBalanceInOf[_cERC20CollateralAddress][_borrower]
            .onComp
            .mul(cERC20CollateralToken.exchangeRateStored());
        uint256 totalCollateral = vars.collateralOnCompInUnderlying +
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P.mul(
                marketsManagerForCompLike.updateMUnitExchangeRate(_cERC20CollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liquidate:to-seize>collateral");

        _withdraw(_cERC20CollateralAddress, vars.amountToSeize, _borrower, msg.sender);
    }

    /* Internal */

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     *  @param _holder the user to whom Morpho will withdraw the supply.
     *  @param _receiver The address of the user that will receive the tokens.
     */
    function _withdraw(
        address _cERC20Address,
        uint256 _amount,
        address _holder,
        address _receiver
    ) internal isMarketCreated(_cERC20Address) {
        require(_amount > 0, "_withdraw:amount=0");
        _checkAccountLiquidity(_holder, _cERC20Address, _amount, 0);
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Compound */
        if (supplyBalanceInOf[_cERC20Address][_holder].onComp > 0) {
            uint256 amountOnCompInUnderlying = supplyBalanceInOf[_cERC20Address][_holder]
                .onComp
                .mul(cExchangeRate);
            /* CASE 1: User withdraws less than his Compound supply balance */
            if (_amount <= amountOnCompInUnderlying) {
                _withdrawERC20FromCompound(_cERC20Address, _amount); // Revert on error
                supplyBalanceInOf[_cERC20Address][_holder].onComp -= _amount.div(cExchangeRate); // In cToken
                remainingToWithdraw = 0; // In underlying
            }
            /* CASE 2: User withdraws more than his Compound supply balance */
            else {
                _withdrawERC20FromCompound(_cERC20Address, amountOnCompInUnderlying); // Revert on error
                supplyBalanceInOf[_cERC20Address][_holder].onComp -= amountOnCompInUnderlying.div(
                    cExchangeRate
                ); // Not set to 0 due to rounding errors.
                remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Compound itself */
        if (remainingToWithdraw > 0) {
            uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);
            uint256 cTokenContractBalanceInUnderlying = cERC20Token.balanceOf(address(this)).mul(
                cExchangeRate
            );
            /* CASE 1: Other suppliers have enough tokens on Compound to compensate user's position*/
            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                require(
                    _matchSuppliers(_cERC20Address, remainingToWithdraw) == 0,
                    "_withdraw:_matchSuppliers!=0"
                );
                supplyBalanceInOf[_cERC20Address][_holder].inP2P -= remainingToWithdraw.div(
                    mExchangeRate
                ); // In mUnit
            }
            /* CASE 2: Other suppliers don't have enough tokens on Compound. Such scenario is called the Hard-Withdraw */
            else {
                uint256 remaining = _matchSuppliers(
                    _cERC20Address,
                    cTokenContractBalanceInUnderlying
                );
                supplyBalanceInOf[_cERC20Address][_holder].inP2P -= remainingToWithdraw.div(
                    mExchangeRate
                ); // In mUnit
                remainingToWithdraw -= remaining;
                require(
                    _unmatchBorrowers(_cERC20Address, remainingToWithdraw) == 0, // We break some P2P credit lines the user had with borrowers and fallback on Compound.
                    "_withdraw:_unmatchBorrowers!=0"
                );
            }
        }

        _updateSupplierList(_cERC20Address, _holder);
        erc20Token.safeTransfer(_receiver, _amount);
        emit Withdrawn(_holder, _cERC20Address, _amount);
    }

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrow.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _cERC20Address,
        address _borrower,
        uint256 _amount
    ) internal isMarketCreated(_cERC20Address) {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Compound */
        if (borrowBalanceInOf[_cERC20Address][_borrower].onComp > 0) {
            uint256 borrowIndex = cERC20Token.borrowIndex();
            uint256 onCompInUnderlying = borrowBalanceInOf[_cERC20Address][_borrower].onComp.mul(
                borrowIndex
            );
            /* CASE 1: User repays less than his Compound borrow balance */
            if (_amount <= onCompInUnderlying) {
                erc20Token.safeApprove(_cERC20Address, _amount);
                cERC20Token.repayBorrow(_amount);
                borrowBalanceInOf[_cERC20Address][_borrower].onComp -= _amount.div(borrowIndex); // In cdUnit
                remainingToRepay = 0;
            }
            /* CASE 2: User repays more than his Compound borrow balance */
            else {
                erc20Token.safeApprove(_cERC20Address, onCompInUnderlying);
                cERC20Token.repayBorrow(onCompInUnderlying); // Revert on error
                borrowBalanceInOf[_cERC20Address][_borrower].onComp = 0;
                remainingToRepay -= onCompInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Compound itself */
        if (remainingToRepay > 0) {
            // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
            uint256 mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                _cERC20Address
            );
            uint256 contractBorrowBalanceOnComp = cERC20Token.borrowBalanceCurrent(address(this)); // In underlying
            /* CASE 1: Other borrowers are borrowing enough on Compound to compensate user's position */
            if (remainingToRepay <= contractBorrowBalanceOnComp) {
                _matchBorrowers(_cERC20Address, remainingToRepay);
                borrowBalanceInOf[_cERC20Address][_borrower].inP2P -= remainingToRepay.div(
                    mExchangeRate
                );
            }
            /* CASE 2: Other borrowers aren't borrowing enough on Compound to compensate user's position */
            else {
                _matchBorrowers(_cERC20Address, contractBorrowBalanceOnComp);
                borrowBalanceInOf[_cERC20Address][_borrower].inP2P -= remainingToRepay.div(
                    mExchangeRate
                ); // In mUnit
                remainingToRepay -= contractBorrowBalanceOnComp;
                require(
                    _unmatchSuppliers(_cERC20Address, remainingToRepay) == 0, // We break some P2P credit lines the user had with suppliers and fallback on Compound.
                    "_repay:_unmatchSuppliers!=0"
                );
            }
        }

        _updateBorrowerList(_cERC20Address, _borrower);
        emit Repaid(_borrower, _cERC20Address, _amount);
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyERC20ToComp(address _cERC20Address, uint256 _amount) internal {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        erc20Token.safeApprove(_cERC20Address, _amount);
        require(cERC20Token.mint(_amount) == 0, "_supplyERC20ToComp:mint-compound-fail");
    }

    /** @dev Withdraws ERC20 tokens from Compound.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromCompound(address _cERC20Address, uint256 _amount) internal {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        require(
            cERC20Token.redeemUnderlying(_amount) == 0,
            "_withdrawERC20FromCompound:redeem-compound-fail"
        );
    }

    /** @dev Finds liquidity on Compound and matches it in P2P.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMatch The remaining liquidity to search for in underlying.
     */
    function _matchSuppliers(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToMatch = _amount; // In underlying
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 highestValue = suppliersOnComp[_cERC20Address].last();

        while (remainingToMatch > 0 && highestValue != 0) {
            // Loop on the keys (addresses) sharing the same value
            while (suppliersOnComp[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnComp[_cERC20Address].valueKeyAtIndex(highestValue, 0); // Pick the first account in the list
                // Check if this user is not borrowing on Compound (cf Liquidation Invariant in docs)
                if (!_hasDebtOnComp(account)) {
                    uint256 onComp = supplyBalanceInOf[_cERC20Address][account].onComp; // In cToken
                    uint256 toMatch;
                    // This is done to prevent rounding errors
                    if (onComp.mul(cExchangeRate) <= remainingToMatch) {
                        supplyBalanceInOf[_cERC20Address][account].onComp = 0;
                        toMatch = onComp.mul(cExchangeRate);
                    } else {
                        toMatch = remainingToMatch;
                        supplyBalanceInOf[_cERC20Address][account].onComp -= toMatch.div(
                            cExchangeRate
                        ); // In cToken
                    }
                    remainingToMatch -= toMatch;
                    supplyBalanceInOf[_cERC20Address][account].inP2P += toMatch.div(mExchangeRate); // In mUnit
                    _updateSupplierList(_cERC20Address, account);
                    emit SupplierMatched(account, _cERC20Address, toMatch);
                }
            }
            // Update the highest value after the tree has been updated
            highestValue = suppliersOnComp[_cERC20Address].last();
        }
        // Withdraw from Compound
        _withdrawERC20FromCompound(_cERC20Address, _amount - remainingToMatch);
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchSuppliers(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToUnmatch = _amount; // In underlying
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);
        uint256 highestValue = suppliersInP2P[_cERC20Address].last();

        while (remainingToUnmatch > 0 && highestValue != 0) {
            while (suppliersInP2P[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersInP2P[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = supplyBalanceInOf[_cERC20Address][account].inP2P; // In cToken
                uint256 toUnmatch = Math.min(inP2P.mul(mExchangeRate), remainingToUnmatch); // In underlying
                remainingToUnmatch -= toUnmatch;
                supplyBalanceInOf[_cERC20Address][account].onComp += toUnmatch.div(cExchangeRate); // In cToken
                supplyBalanceInOf[_cERC20Address][account].inP2P -= toUnmatch.div(mExchangeRate); // In mUnit
                _updateSupplierList(_cERC20Address, account);
                emit SupplierUnmatched(account, _cERC20Address, toUnmatch);
            }
            highestValue = suppliersInP2P[_cERC20Address].last();
        }
        // Supply on Compound
        _supplyERC20ToComp(_cERC20Address, _amount - remainingToUnmatch);
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and move them in P2P.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _matchBorrowers(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        remainingToMatch = _amount;
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);
        uint256 borrowIndex = cERC20Token.borrowIndex();
        uint256 highestValue = borrowersOnComp[_cERC20Address].last();

        while (remainingToMatch > 0 && highestValue != 0) {
            while (borrowersOnComp[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnComp[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 onComp = borrowBalanceInOf[_cERC20Address][account].onComp; // In cToken
                uint256 toMatch;
                if (onComp.mul(borrowIndex) <= remainingToMatch) {
                    toMatch = onComp.mul(borrowIndex);
                    borrowBalanceInOf[_cERC20Address][account].onComp = 0;
                } else {
                    toMatch = remainingToMatch;
                    borrowBalanceInOf[_cERC20Address][account].onComp -= toMatch.div(borrowIndex);
                }
                remainingToMatch -= toMatch;
                borrowBalanceInOf[_cERC20Address][account].inP2P += toMatch.div(mExchangeRate);
                _updateBorrowerList(_cERC20Address, account);
                emit BorrowerMatched(account, _cERC20Address, toMatch);
            }
            highestValue = borrowersOnComp[_cERC20Address].last();
        }
        // Repay Compound
        uint256 toRepay = _amount - remainingToMatch;
        erc20Token.safeApprove(_cERC20Address, toRepay);
        require(cERC20Token.repayBorrow(toRepay) == 0, "_matchBorrowers:repay-compound-fail");
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchBorrowers(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToUnmatch = _amount;
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_cERC20Address);
        uint256 borrowIndex = cERC20Token.borrowIndex();
        uint256 highestValue = borrowersInP2P[_cERC20Address].last();

        while (remainingToUnmatch > 0 && highestValue != 0) {
            while (borrowersInP2P[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersInP2P[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = borrowBalanceInOf[_cERC20Address][account].inP2P;
                _unmatchTheSupplier(account); // Before borrowing on Compound, we put all the collateral of the borrower on Compound (cf Liquidation Invariant in docs)
                uint256 toUnmatch = Math.min(inP2P.mul(mExchangeRate), remainingToUnmatch); // In underlying
                remainingToUnmatch -= toUnmatch;
                borrowBalanceInOf[_cERC20Address][account].onComp += toUnmatch.div(borrowIndex);
                borrowBalanceInOf[_cERC20Address][account].inP2P -= toUnmatch.div(mExchangeRate);
                _updateBorrowerList(_cERC20Address, account);
                emit BorrowerUnmatched(account, _cERC20Address, toUnmatch);
            }
            highestValue = borrowersInP2P[_cERC20Address].last();
        }
        // Borrow on Compound
        require(cERC20Token.borrow(_amount - remainingToUnmatch) == 0);
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Compound.
     * @param _account The address of the account to move balance.
     */
    function _unmatchTheSupplier(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cERC20Entered = enteredMarkets[_account][i];
            uint256 inP2P = supplyBalanceInOf[cERC20Entered][_account].inP2P;

            if (inP2P > 0) {
                uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(cERC20Entered);
                uint256 cExchangeRate = ICErc20(cERC20Entered).exchangeRateCurrent();
                uint256 inP2PInUnderlying = inP2P.mul(mExchangeRate);
                supplyBalanceInOf[cERC20Entered][_account].onComp += inP2PInUnderlying.div(
                    cExchangeRate
                ); // In cToken
                supplyBalanceInOf[cERC20Entered][_account].inP2P -= inP2PInUnderlying.div(
                    mExchangeRate
                ); // In mUnit
                _unmatchBorrowers(cERC20Entered, inP2PInUnderlying);
                _updateSupplierList(cERC20Entered, _account);
                // Supply to Compound
                _supplyERC20ToComp(cERC20Entered, inP2PInUnderlying);
                emit SupplierUnmatched(_account, cERC20Entered, inP2PInUnderlying);
            }
        }
    }

    /**
     * @dev Enters the user into the market if he is not already there.
     * @param _account The address of the account to update.
     * @param _cTokenAddress The address of the market to check.
     */
    function _handleMembership(address _cTokenAddress, address _account) internal {
        if (!accountMembership[_cTokenAddress][_account]) {
            accountMembership[_cTokenAddress][_account] = true;
            enteredMarkets[_account].push(_cTokenAddress);
        }
    }

    /** @dev Checks whether the user can borrow/withdraw or not.
     *  @param _account The user to determine liquidity for.
     *  @param _cERC20Address The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     */
    function _checkAccountLiquidity(
        address _account,
        address _cERC20Address,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _account,
            _cERC20Address,
            _withdrawnAmount,
            _borrowedAmount
        );
        require(debtValue < maxDebtValue, "_checkAccountLiquidity:debt-value>max");
    }

    /** @dev Returns the debt value, max debt value and collateral value of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _cERC20Address The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtValue, maxDebtValue collateralValue).
     */
    function _getUserHypotheticalBalanceStates(
        address _account,
        address _cERC20Address,
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
            vars.mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                vars.cERC20Entered
            );
            // Calculation of the current debt (in underlying)
            vars.debtToAdd =
                borrowBalanceInOf[vars.cERC20Entered][_account].onComp.mul(
                    ICErc20(vars.cERC20Entered).borrowIndex()
                ) +
                borrowBalanceInOf[vars.cERC20Entered][_account].inP2P.mul(vars.mExchangeRate);
            // Calculation of the current collateral (in underlying)
            vars.collateralToAdd =
                supplyBalanceInOf[vars.cERC20Entered][_account].onComp.mul(
                    ICErc20(vars.cERC20Entered).exchangeRateCurrent()
                ) +
                supplyBalanceInOf[vars.cERC20Entered][_account].inP2P.mul(vars.mExchangeRate);
            // Price recovery
            vars.underlyingPrice = compoundOracle.getUnderlyingPrice(vars.cERC20Entered);
            require(vars.underlyingPrice != 0, "_getUserHypotheticalBalanceStates:oracle-fail");

            if (_cERC20Address == vars.cERC20Entered) {
                vars.debtToAdd += _borrowedAmount;
                balanceState.redeemedValue = _withdrawnAmount.mul(vars.underlyingPrice);
            }
            // Conversion of the collateral to dollars
            vars.collateralToAdd = vars.collateralToAdd.mul(vars.underlyingPrice);
            // Add the debt in this market to the global debt (in dollars)
            balanceState.debtValue += vars.debtToAdd.mul(vars.underlyingPrice);
            // Add the collateral value in this asset to the global collateral value (in dollars)
            balanceState.collateralValue += vars.collateralToAdd;
            (, uint256 collateralFactorMantissa, ) = comptroller.markets(vars.cERC20Entered);
            // Add the max debt value allowed by the collateral in this asset to the global max debt value (in dollars)
            balanceState.maxDebtValue += vars.collateralToAdd.mul(collateralFactorMantissa);
        }

        balanceState.collateralValue -= balanceState.redeemedValue;

        return (balanceState.debtValue, balanceState.maxDebtValue, balanceState.collateralValue);
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _cERC20Address The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function _updateBorrowerList(address _cERC20Address, address _account) internal {
        if (borrowersOnComp[_cERC20Address].keyExists(_account))
            borrowersOnComp[_cERC20Address].remove(_account);
        if (borrowersInP2P[_cERC20Address].keyExists(_account))
            borrowersInP2P[_cERC20Address].remove(_account);
        uint256 onComp = borrowBalanceInOf[_cERC20Address][_account].onComp;
        if (onComp > 0) {
            borrowersOnComp[_cERC20Address].insert(_account, onComp);
        }
        uint256 inP2P = borrowBalanceInOf[_cERC20Address][_account].inP2P;
        if (inP2P > 0) {
            borrowersInP2P[_cERC20Address].insert(_account, inP2P);
        }
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _cERC20Address The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function _updateSupplierList(address _cERC20Address, address _account) internal {
        if (suppliersOnComp[_cERC20Address].keyExists(_account))
            suppliersOnComp[_cERC20Address].remove(_account);
        if (suppliersInP2P[_cERC20Address].keyExists(_account))
            suppliersInP2P[_cERC20Address].remove(_account);
        uint256 onComp = supplyBalanceInOf[_cERC20Address][_account].onComp;
        if (onComp > 0) {
            suppliersOnComp[_cERC20Address].insert(_account, onComp);
        }
        uint256 inP2P = supplyBalanceInOf[_cERC20Address][_account].inP2P;
        if (inP2P > 0) {
            suppliersInP2P[_cERC20Address].insert(_account, inP2P);
        }
    }

    function _hasDebtOnComp(address _account) internal view returns (bool) {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            if (borrowBalanceInOf[enteredMarkets[_account][i]][_account].onComp > 0) {
                return true;
            }
        }
        return false;
    }
}
