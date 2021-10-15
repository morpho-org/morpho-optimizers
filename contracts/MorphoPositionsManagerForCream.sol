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
 *  @title MorphoPositionsManagerForCream
 *  @dev Smart contract interacting with Cream to enable P2P supply/borrow positions that can fallback on Cream's pool using cERC20 tokens.
 */
contract MorphoPositionsManagerForCream is ReentrancyGuard {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In mUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onCream; // In crToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In mUnit.
        uint256 onCream; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Cream. Multiply by current borrowIndex to get the underlying amount.
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

    mapping(address => RedBlackBinaryTree.Tree) private suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private suppliersOnCream; // Suppliers on Cream.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersOnCream; // Borrowers on Cream.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public thresholds; // Thresholds below the ones suppliers and borrowers cannot enter markets.
    mapping(address => bool) public isListed; // Whether or not this market is listed.

    IComptroller public creamtroller;
    ICompoundOracle public creamOracle;
    IMarketsManagerForCompLike public marketsManagerForCompLike;

    /* Events */

    /** @dev Emitted when a supply happens.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market where assets are supplied into.
     *  @param _amount The amount of assets.
     */
    event Supplied(address indexed _account, address indexed _crERC20Address, uint256 _amount);

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

    /** @dev Emitted when a repay happens.
     *  @param _account The address of the repayer.
     *  @param _crERC20Address The address of the market where assets are repaid.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _crERC20Address, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Cream to P2P.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMatched(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from P2P to Cream.
     *  @param _account The address of the supplier.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierUnmatched(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Cream to P2P.
     *  @param _account The address of the borrower.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMatched(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from P2P to Cream.
     *  @param _account The address of the borrower.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerUnmatched(
        address indexed _account,
        address indexed _crERC20Address,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not listed.
     *  @param _crERC20Address The address of the market.
     */
    modifier isMarketListed(address _crERC20Address) {
        require(isListed[_crERC20Address], "mkt-not-listed");
        _;
    }

    /** @dev Prevents a user to supply or borrow less than threshold.
     *  @param _crERC20Address The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _crERC20Address, uint256 _amount) {
        require(_amount >= thresholds[_crERC20Address], "amount<threshold");
        _;
    }

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(marketsManagerForCompLike), "only-mkt-manager");
        _;
    }

    /* Constructor */

    constructor(address _creamMarketsManager, address _proxyCreamtrollerAddress) {
        marketsManagerForCompLike = IMarketsManagerForCompLike(_creamMarketsManager);
        creamtroller = IComptroller(_proxyCreamtrollerAddress);
        creamOracle = ICompoundOracle(creamtroller.oracle());
    }

    /* External */

    /** @dev Creates Cream's markets.
     *  @param markets The address of the market the user wants to supply.
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

    /** @dev Sets the listing of a market.
     *  @param _crERC20Address The address of the market to list or delist.
     *  @param _listing Whether to list the market or not.
     */
    function setListing(address _crERC20Address, bool _listing) external onlyMarketsManager {
        isListed[_crERC20Address] = _listing;
    }

    /** @dev Sets the threshold of a market.
     *  @param _crERC20Address The address of the market to set the threshold.
     *  @param _newThreshold The new threshold.
     */
    function setThreshold(address _crERC20Address, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        thresholds[_crERC20Address] = _newThreshold;
    }

    /** @dev Supplies ERC20 tokens in a specific market.
     *  @param _crERC20Address The address of the market the user wants to supply.
     *  @param _amount The amount to supply in ERC20 tokens.
     */
    function supply(address _crERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_crERC20Address)
        isAboveThreshold(_crERC20Address, _amount)
    {
        _handleMembership(_crERC20Address, msg.sender);
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 crExchangeRate = crERC20Token.exchangeRateCurrent();

        /* CASE 1: Some borrowers are waiting on Cream, Morpho matches the supplier in P2P with them */
        if (borrowersOnCream[_crERC20Address].isNotEmpty()) {
            uint256 mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                _crERC20Address
            );
            uint256 remainingToSupplyToCream = _matchBorrowers(_crERC20Address, _amount); // In underlying
            uint256 matched = _amount - remainingToSupplyToCream;
            if (matched > 0) {
                supplyBalanceInOf[_crERC20Address][msg.sender].inP2P += matched.div(mExchangeRate); // In mUnit
            }
            /* If there aren't enough borrowers waiting on Cream to match all the tokens supplied, the rest is supplied to Cream */
            if (remainingToSupplyToCream > 0) {
                supplyBalanceInOf[_crERC20Address][msg.sender].onCream += remainingToSupplyToCream
                    .div(crExchangeRate); // In crToken
                _supplyERC20ToCream(_crERC20Address, remainingToSupplyToCream); // Revert on error
            }
        }
        /* CASE 2: There aren't any borrowers waiting on Cream, Morpho supplies all the tokens to Cream */
        else {
            supplyBalanceInOf[_crERC20Address][msg.sender].onCream += _amount.div(crExchangeRate); // In crToken
            _supplyERC20ToCream(_crERC20Address, _amount); // Revert on error
        }

        _updateSupplierList(_crERC20Address, msg.sender);
        emit Supplied(msg.sender, _crERC20Address, _amount);
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
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);

        /* CASE 1: Some suppliers are waiting on Cream, Morpho matches the borrower in P2P with them */
        if (suppliersOnCream[_crERC20Address].isNotEmpty()) {
            uint256 remainingToBorrowOnCream = _matchSuppliers(_crERC20Address, _amount); // In underlying
            uint256 matched = _amount - remainingToBorrowOnCream;

            if (matched > 0) {
                borrowBalanceInOf[_crERC20Address][msg.sender].inP2P += matched.div(mExchangeRate); // In mUnit
            }

            /* If there aren't enough suppliers waiting on Cream to match all the tokens borrowed, the rest is borrowed from Cream */
            if (remainingToBorrowOnCream > 0) {
                _unmatchTheSupplier(msg.sender); // Before borrowing on Cream, we put all the collateral of the borrower on Cream (cf Liquidation Invariant in docs)
                require(
                    crERC20Token.borrow(remainingToBorrowOnCream) == 0,
                    "borrow(1):borrow-cream-fail"
                );
                borrowBalanceInOf[_crERC20Address][msg.sender].onCream += remainingToBorrowOnCream
                    .div(crERC20Token.borrowIndex()); // In cdUnit
            }
        }
        /* CASE 2: There aren't any borrowers waiting on Cream, Morpho borrows all the tokens from Cream */
        else {
            _unmatchTheSupplier(msg.sender); // Before borrowing on Cream, we put all the collateral of the borrower on Cream (cf Liquidation Invariant in docs)
            require(crERC20Token.borrow(_amount) == 0, "borrow(2):borrow-cream-fail");
            borrowBalanceInOf[_crERC20Address][msg.sender].onCream += _amount.div(
                crERC20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_crERC20Address, msg.sender);
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _crERC20Address, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _crERC20Address, uint256 _amount) external nonReentrant {
        _withdraw(_crERC20Address, _amount, msg.sender, msg.sender);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _crERC20Address, uint256 _amount) external nonReentrant {
        _repay(_crERC20Address, msg.sender, _amount);
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
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].onCream.mul(
                ICErc20(_cERC20BorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].inP2P.mul(
                marketsManagerForCompLike.mUnitExchangeRate(_cERC20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(creamtroller.closeFactorMantissa()),
            "liquidate:amount>allowed"
        );

        _repay(_cERC20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = creamOracle.getUnderlyingPrice(_cERC20CollateralAddress);
        vars.priceBorrowedMantissa = creamOracle.getUnderlyingPrice(_cERC20BorrowedAddress);
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
            .mul(creamtroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.onCreamInUnderlying = supplyBalanceInOf[_cERC20CollateralAddress][_borrower]
            .onCream
            .mul(cERC20CollateralToken.exchangeRateStored());
        uint256 totalCollateral = vars.onCreamInUnderlying +
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P.mul(
                marketsManagerForCompLike.updateMUnitExchangeRate(_cERC20CollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liquidate:to-seize>collateral");

        _withdraw(_cERC20CollateralAddress, vars.amountToSeize, _borrower, msg.sender);
    }

    /* Internal */

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     *  @param _holder the user to whom Morpho will withdraw the supply.
     *  @param _receiver The address of the user that will receive the tokens.
     */
    function _withdraw(
        address _crERC20Address,
        uint256 _amount,
        address _holder,
        address _receiver
    ) internal isMarketListed(_crERC20Address) {
        require(_amount > 0, "_withdraw:amount=0");
        _checkAccountLiquidity(_holder, _crERC20Address, _amount, 0);
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
        uint256 crExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Cream */
        if (supplyBalanceInOf[_crERC20Address][_holder].onCream > 0) {
            uint256 amountOnCreamInUnderlying = supplyBalanceInOf[_crERC20Address][_holder]
                .onCream
                .mul(crExchangeRate);
            /* CASE 1: User withdraws less than his Cream supply balance */
            if (_amount <= amountOnCreamInUnderlying) {
                _withdrawERC20FromCream(_crERC20Address, _amount); // Revert on error
                supplyBalanceInOf[_crERC20Address][_holder].onCream -= _amount.div(crExchangeRate); // In crToken
                remainingToWithdraw = 0; // In underlying
            }
            /* CASE 2: User withdraws more than his Cream supply balance */
            else {
                _withdrawERC20FromCream(_crERC20Address, amountOnCreamInUnderlying); // Revert on error
                supplyBalanceInOf[_crERC20Address][_holder].onCream -= amountOnCreamInUnderlying
                    .div(crExchangeRate); // Not set to 0 due to rounding errors.
                remainingToWithdraw = _amount - amountOnCreamInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Cream itself */
        if (remainingToWithdraw > 0) {
            uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);
            uint256 crTokenContractBalanceInUnderlying = crERC20Token.balanceOf(address(this)).mul(
                crExchangeRate
            );
            /* CASE 1: Other suppliers have enough tokens on Cream to compensate user's position*/
            if (remainingToWithdraw <= crTokenContractBalanceInUnderlying) {
                require(
                    _matchSuppliers(_crERC20Address, remainingToWithdraw) == 0,
                    "_withdraw:_matchSuppliers!=0"
                );
                supplyBalanceInOf[_crERC20Address][_holder].inP2P -= remainingToWithdraw.div(
                    mExchangeRate
                ); // In mUnit
            }
            /* CASE 2: Other suppliers don't have enough tokens on Cream. Such scenario is called the Hard-Withdraw */
            else {
                uint256 remaining = _matchSuppliers(
                    _crERC20Address,
                    crTokenContractBalanceInUnderlying
                );
                supplyBalanceInOf[_crERC20Address][_holder].inP2P -= remainingToWithdraw.div(
                    mExchangeRate
                ); // In mUnit
                remainingToWithdraw -= remaining;
                require(
                    _unmatchBorrowers(_crERC20Address, remainingToWithdraw) == 0,
                    "_withdraw:_unmatchBorrowers!=0"
                );
            }
        }

        _updateSupplierList(_crERC20Address, _holder);
        erc20Token.safeTransfer(_receiver, _amount);
        emit Withdrawn(_holder, _crERC20Address, _amount);
    }

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

        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Cream */
        if (borrowBalanceInOf[_crERC20Address][_borrower].onCream > 0) {
            uint256 borrowIndex = crERC20Token.borrowIndex();
            uint256 onCreamInUnderlying = borrowBalanceInOf[_crERC20Address][_borrower].onCream.mul(
                borrowIndex
            );
            /* CASE 1: User repays less than his Cream borrow balance */
            if (_amount <= onCreamInUnderlying) {
                erc20Token.safeApprove(_crERC20Address, _amount);
                crERC20Token.repayBorrow(_amount);
                borrowBalanceInOf[_crERC20Address][_borrower].onCream -= _amount.div(borrowIndex); // In cdUnit
                remainingToRepay = 0;
            }
            /* CASE 2: User repays more than his Cream borrow balance */
            else {
                erc20Token.safeApprove(_crERC20Address, onCreamInUnderlying);
                crERC20Token.repayBorrow(onCreamInUnderlying); // Revert on error
                borrowBalanceInOf[_crERC20Address][_borrower].onCream = 0;
                remainingToRepay -= onCreamInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Cream itself */
        if (remainingToRepay > 0) {
            // No need to update mUnitExchangeRate here as it's done in `_checkAccountLiquidity`
            uint256 mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                _crERC20Address
            );
            uint256 contractBorrowBalanceOnCream = crERC20Token.borrowBalanceCurrent(address(this)); // In underlying
            /* CASE 1: Other borrowers are borrowing enough on Cream to compensate user's position */
            if (remainingToRepay <= contractBorrowBalanceOnCream) {
                _matchBorrowers(_crERC20Address, remainingToRepay);
                borrowBalanceInOf[_crERC20Address][_borrower].inP2P -= remainingToRepay.div(
                    mExchangeRate
                );
            }
            /* CASE 2: Other borrowers aren't borrowing enough on Cream to compensate user's position */
            else {
                _matchBorrowers(_crERC20Address, contractBorrowBalanceOnCream);
                borrowBalanceInOf[_crERC20Address][_borrower].inP2P -= remainingToRepay.div(
                    mExchangeRate
                ); // In mUnit
                remainingToRepay -= contractBorrowBalanceOnCream;
                require(
                    _unmatchSuppliers(_crERC20Address, remainingToRepay) == 0,
                    "_repay:_unmatchSuppliers!=0"
                );
            }
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
        require(crERC20Token.mint(_amount) == 0, "_supplyERC20ToCream:mint-cream-fail");
    }

    /** @dev Withdraws ERC20 tokens from Cream.
     *  @param _crERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromCream(address _crERC20Address, uint256 _amount) internal {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        require(
            crERC20Token.redeemUnderlying(_amount) == 0,
            "_withdrawERC20FromCream:redeem-cream-fail"
        );
    }

    /** @dev Finds liquidity on Cream and matches it in P2P.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMatch The remaining liquidity to search for in underlying.
     */
    function _matchSuppliers(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToMatch = _amount; // In underlying
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);
        uint256 crExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 highestValue = suppliersOnCream[_crERC20Address].last();

        while (remainingToMatch > 0 && highestValue != 0) {
            // Loop on the keys (addresses) sharing the same value
            while (suppliersOnCream[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnCream[_crERC20Address].valueKeyAtIndex(
                    highestValue,
                    0
                ); // Pick the first account in the list
                // Check if this user is not borrowing on Cream
                if (!_hasDebtOnCream(account)) {
                    uint256 onCream = supplyBalanceInOf[_crERC20Address][account].onCream; // In crToken
                    uint256 toMatch;
                    // This is done to prevent rounding errors
                    if (onCream.mul(crExchangeRate) <= remainingToMatch) {
                        supplyBalanceInOf[_crERC20Address][account].onCream = 0;
                        toMatch = onCream.mul(crExchangeRate);
                    } else {
                        toMatch = remainingToMatch;
                        supplyBalanceInOf[_crERC20Address][account].onCream -= toMatch.div(
                            crExchangeRate
                        ); // In crToken
                    }
                    remainingToMatch -= toMatch;
                    supplyBalanceInOf[_crERC20Address][account].inP2P += toMatch.div(mExchangeRate); // In mUnit
                    _updateSupplierList(_crERC20Address, account);
                    emit SupplierMatched(account, _crERC20Address, toMatch);
                }
            }
            // Update the highest value after the tree has been updated
            highestValue = suppliersOnCream[_crERC20Address].last();
        }
        // Withdraw from Cream
        _withdrawERC20FromCream(_crERC20Address, _amount - remainingToMatch);
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Cream.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchSuppliers(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToUnmatch = _amount; // In underlying
        uint256 crExchangeRate = crERC20Token.exchangeRateCurrent();
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);
        uint256 highestValue = suppliersInP2P[_crERC20Address].last();

        while (remainingToUnmatch > 0 && highestValue != 0) {
            while (suppliersInP2P[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersInP2P[_crERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = supplyBalanceInOf[_crERC20Address][account].inP2P; // In crToken
                uint256 toUnmatch = Math.min(inP2P.mul(mExchangeRate), remainingToUnmatch); // In underlying
                remainingToUnmatch -= toUnmatch;
                supplyBalanceInOf[_crERC20Address][account].onCream += toUnmatch.div(
                    crExchangeRate
                ); // In crToken
                supplyBalanceInOf[_crERC20Address][account].inP2P -= toUnmatch.div(mExchangeRate); // In mUnit
                _updateSupplierList(_crERC20Address, account);
                emit SupplierUnmatched(account, _crERC20Address, toUnmatch);
            }
            highestValue = suppliersInP2P[_crERC20Address].last();
        }
        // Supply on Cream
        _supplyERC20ToCream(_crERC20Address, _amount - remainingToUnmatch);
    }

    /** @dev Finds borrowers on Cream that match the given `_amount` and move them in P2P.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _matchBorrowers(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        IERC20 erc20Token = IERC20(crERC20Token.underlying());
        remainingToMatch = _amount;
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);
        uint256 borrowIndex = crERC20Token.borrowIndex();
        uint256 highestValue = borrowersOnCream[_crERC20Address].last();

        while (remainingToMatch > 0 && highestValue != 0) {
            while (borrowersOnCream[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnCream[_crERC20Address].valueKeyAtIndex(
                    highestValue,
                    0
                );
                uint256 onCream = borrowBalanceInOf[_crERC20Address][account].onCream; // In crToken
                uint256 toMatch;
                if (onCream.mul(borrowIndex) <= remainingToMatch) {
                    toMatch = onCream.mul(borrowIndex);
                    borrowBalanceInOf[_crERC20Address][account].onCream = 0;
                } else {
                    toMatch = remainingToMatch;
                    borrowBalanceInOf[_crERC20Address][account].onCream -= toMatch.div(borrowIndex);
                }
                remainingToMatch -= toMatch;
                borrowBalanceInOf[_crERC20Address][account].inP2P += toMatch.div(mExchangeRate);
                _updateBorrowerList(_crERC20Address, account);
                emit BorrowerMatched(account, _crERC20Address, toMatch);
            }
            highestValue = borrowersOnCream[_crERC20Address].last();
        }
        // Repay Cream
        uint256 toRepay = _amount - remainingToMatch;
        erc20Token.safeApprove(_crERC20Address, toRepay);
        require(crERC20Token.repayBorrow(toRepay) == 0, "_matchBorrowers:repay-cream-fail");
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Cream.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _crERC20Address The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchBorrowers(address _crERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 crERC20Token = ICErc20(_crERC20Address);
        remainingToUnmatch = _amount;
        uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(_crERC20Address);
        uint256 borrowIndex = crERC20Token.borrowIndex();
        uint256 highestValue = borrowersInP2P[_crERC20Address].last();

        while (remainingToUnmatch > 0 && highestValue != 0) {
            while (borrowersInP2P[_crERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersInP2P[_crERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = borrowBalanceInOf[_crERC20Address][account].inP2P;
                _unmatchTheSupplier(account); // Before borrowing on Cream, we put all the collateral of the borrower on Cream (cf Liquidation Invariant in docs)
                uint256 toUnmatch = Math.min(inP2P.mul(mExchangeRate), remainingToUnmatch); // In underlying
                remainingToUnmatch -= toUnmatch;
                borrowBalanceInOf[_crERC20Address][account].onCream += toUnmatch.div(borrowIndex);
                borrowBalanceInOf[_crERC20Address][account].inP2P -= toUnmatch.div(mExchangeRate);
                _updateBorrowerList(_crERC20Address, account);
                emit BorrowerUnmatched(account, _crERC20Address, toUnmatch);
            }
            highestValue = borrowersInP2P[_crERC20Address].last();
        }
        // Borrow on Cream
        require(crERC20Token.borrow(_amount - remainingToUnmatch) == 0);
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Cream.
     * @param _account The address of the account to move balance.
     */
    function _unmatchTheSupplier(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cERC20Entered = enteredMarkets[_account][i];
            uint256 inP2P = supplyBalanceInOf[cERC20Entered][_account].inP2P;

            if (inP2P > 0) {
                uint256 mExchangeRate = marketsManagerForCompLike.mUnitExchangeRate(cERC20Entered);
                uint256 crExchangeRate = ICErc20(cERC20Entered).exchangeRateCurrent();
                uint256 inP2PInUnderlying = inP2P.mul(mExchangeRate);
                supplyBalanceInOf[cERC20Entered][_account].onCream += inP2PInUnderlying.div(
                    crExchangeRate
                ); // In crToken
                supplyBalanceInOf[cERC20Entered][_account].inP2P -= inP2PInUnderlying.div(
                    mExchangeRate
                ); // In mUnit
                _unmatchBorrowers(cERC20Entered, inP2PInUnderlying);
                _updateSupplierList(cERC20Entered, _account);
                // Supply to Cream
                _supplyERC20ToCream(cERC20Entered, inP2PInUnderlying);
                emit SupplierUnmatched(_account, cERC20Entered, inP2PInUnderlying);
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
        require(debtValue < maxDebtValue, "_checkAccountLiquidity:debt-value>max");
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
            vars.mExchangeRate = marketsManagerForCompLike.updateMUnitExchangeRate(
                vars.cERC20Entered
            );
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
            require(vars.underlyingPrice != 0, "_getUserHypotheticalBalanceStates:oracle-fail");

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
        uint256 onCream = borrowBalanceInOf[_crERC20Address][_account].onCream;
        if (onCream > 0) {
            borrowersOnCream[_crERC20Address].insert(_account, onCream);
        }
        uint256 inP2P = borrowBalanceInOf[_crERC20Address][_account].inP2P;
        if (inP2P > 0) {
            borrowersInP2P[_crERC20Address].insert(_account, inP2P);
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
        uint256 onCream = supplyBalanceInOf[_crERC20Address][_account].onCream;
        if (onCream > 0) {
            suppliersOnCream[_crERC20Address].insert(_account, onCream);
        }
        uint256 inP2P = supplyBalanceInOf[_crERC20Address][_account].inP2P;
        if (inP2P > 0) {
            suppliersInP2P[_crERC20Address].insert(_account, inP2P);
        }
    }

    function _hasDebtOnCream(address _account) internal view returns (bool) {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            if (borrowBalanceInOf[enteredMarkets[_account][i]][_account].onCream > 0) {
                return true;
            }
        }
        return false;
    }
}
