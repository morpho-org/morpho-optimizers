// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libraries/SafeERC20.sol";
import "./compound-math/CompoundMath.sol";
import "./libraries/RedBlackBinaryTree.sol";
import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IMarketsManagerForCompound.sol";

/**
 *  @title MorphoPositionsManagerForComp
 *  @dev Smart contract interacting with Comp to enable P2P supply/borrow positions that can fallback on Comp's pool using cToken tokens.
 */
contract MorphoPositionsManagerForCompound is ReentrancyGuard {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using EnumerableSet for EnumerableSet.AddressSet;
    using CompoundMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In p2pUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onPool; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In p2pUnit.
        uint256 onPool; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Comp. Multiply by current borrowIndex to get the underlying amount.
    }

    // Struct to avoid stack too deep error
    struct BalanceStateVars {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 redeemedValue; // The redeemed value if any (in USD).
        uint256 collateralValue; // The collateral value (in USD).
        uint256 debtToAdd; // The debt to add at the current iteration.
        uint256 collateralToAdd; // The collateral to add at the current iteration.
        address cTokenEntered; // The cToken token entered by the user.
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

    uint8 constant private CTOKEN_DECIMALS = 8;

    /* Storage */

    uint16 public NMAX = 1000;
    mapping(address => RedBlackBinaryTree.Tree) private suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private suppliersOnPool; // Suppliers on Comp.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) private borrowersOnPool; // Borrowers on Comp.
    mapping(address => EnumerableSet.AddressSet) private suppliersInP2PBuffer; // Buffer of suppliers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) private suppliersOnPoolBuffer; // Buffer of suppliers on Comp.
    mapping(address => EnumerableSet.AddressSet) private borrowersInP2PBuffer; // Buffer of borrowers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) private borrowersOnPoolBuffer; // Buffer of borrowers on Comp.
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
     *  @param _cTokenAddress The address of the market where assets are supplied into.
     *  @param _amount The amount of assets.
     */
    event Supplied(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Emitted when a withdraw happens.
     *  @param _account The address of the withdrawer.
     *  @param _cTokenAddress The address of the market from where assets are withdrawn.
     *  @param _amount The amount of assets.
     */
    event Withdrawn(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _cTokenAddress The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrowed(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Emitted when a repay happens.
     *  @param _account The address of the repayer.
     *  @param _cTokenAddress The address of the market where assets are repaid.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _cTokenAddress, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Comp to P2P.
     *  @param _account The address of the supplier.
     *  @param _cTokenAddress The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMatched(
        address indexed _account,
        address indexed _cTokenAddress,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from P2P to Comp.
     *  @param _account The address of the supplier.
     *  @param _cTokenAddress The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierUnmatched(
        address indexed _account,
        address indexed _cTokenAddress,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Comp to P2P.
     *  @param _account The address of the borrower.
     *  @param _cTokenAddress The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMatched(
        address indexed _account,
        address indexed _cTokenAddress,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from P2P to Comp.
     *  @param _account The address of the borrower.
     *  @param _cTokenAddress The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerUnmatched(
        address indexed _account,
        address indexed _cTokenAddress,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not created yet.
     *  @param _cTokenAddress The address of the market.
     */
    modifier isMarketCreated(address _cTokenAddress) {
        require(marketsManagerForCompound.isCreated(_cTokenAddress), "mkt-not-created");
        _;
    }

    /** @dev Prevents a user to supply or borrow less than threshold.
     *  @param _cTokenAddress The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _cTokenAddress, uint256 _amount) {
        require(_amount >= threshold[_cTokenAddress], "amount<threshold");
        _;
    }

    /** @dev Prevents a user to call function only allowed for the markets manager.
     */
    modifier onlyMarketsManager() {
        require(msg.sender == address(marketsManagerForCompound), "only-mkt-manager");
        _;
    }

    /** @dev Skips the operation if it is unsafe due to coumpound's revert on low levels of precision
     *  @param _amount The amount of token considered for depositing/redeeming
     *  @param _cTokenAddress cToken address of the considered market
     */
    modifier isAboveCompoundThreshold(address _cTokenAddress, uint256 _amount){
        IERC20Metadata token = IERC20Metadata(ICErc20(_cTokenAddress).underlying());
        uint8 tokenDecimals = token.decimals();
        if(tokenDecimals > CTOKEN_DECIMALS){
            // we multiply by 2 to have a safety buffer
            if(_amount > 2 * 10 ** (token.decimals() - CTOKEN_DECIMALS)){
                _;
            }
        } else {
            // we multiply by 2 to have a safety buffer
            if(_amount > 2 * 10 ** (CTOKEN_DECIMALS - token.decimals())){
                _;
            }
        }
    }

    /* Constructor */

    /** @dev Constructs the MorphoPositionsManagerForCompound contract.
     *  @param _compoundMarketsManager The address of the markets manager.
     *  @param _proxyComptrollerAddress The address of the proxy comptroller.
     */
    constructor(address _compoundMarketsManager, address _proxyComptrollerAddress) {
        marketsManagerForCompound = IMarketsManagerForCompound(_compoundMarketsManager);
        comptroller = IComptroller(_proxyComptrollerAddress);
    }

    /* External */

    /** @dev Creates Comp's markets.
     *  @param _cTokenAddress The address of the market the user wants to supply.
     *  @return The results of entered.
     */
    function createMarket(address _cTokenAddress)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _cTokenAddress;
        return comptroller.enterMarkets(marketToEnter);
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Comp's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyMarketsManager {
        comptroller = IComptroller(_proxyComptrollerAddress);
    }

    /** @dev Sets the maximum number of users in data structure.
     *  @param _newMaxNumber The maximum number of users to have in the data structure.
     */
    function setMaxNumberOfUsersInDataStructure(uint16 _newMaxNumber) external onlyMarketsManager {
        NMAX = _newMaxNumber;
    }

    /** @dev Sets the threshold of a market.
     *  @param _cTokenAddress The address of the market to set the threshold.
     *  @param _newThreshold The new threshold.
     */
    function setThreshold(address _cTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_cTokenAddress] = _newThreshold;
    }

    /** @dev Supplies ERC20 tokens in a specific market.
     *  @param _cTokenAddress The address of the market the user wants to supply.
     *  @param _amount The amount to supply in ERC20 tokens.
     */
    function supply(address _cTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_cTokenAddress)
        isAboveThreshold(_cTokenAddress, _amount)
    {
        _handleMembership(_cTokenAddress, msg.sender);
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cTokenExchangeRate = cToken.exchangeRateCurrent();
        /* DEFAULT CASE: There aren't any borrowers waiting on Comp, Morpho supplies all the tokens to Comp */
        uint256 remainingToSupplyToPool = _amount;

        /* If some borrowers are waiting on Comp, Morpho matches the supplier in P2P with them as much as possible */
        if (borrowersOnPool[_cTokenAddress].isNotEmpty()) {
            uint256 p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                _cTokenAddress
            );
            remainingToSupplyToPool = _matchBorrowers(_cTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToSupplyToPool;

            if (matched > 0) {
                supplyBalanceInOf[_cTokenAddress][msg.sender].inP2P += matched.div(p2pExchangeRate); // In p2pUnit
            }
        }

        /* If there aren't enough borrowers waiting on Comp to match all the tokens supplied, the rest is supplied to Comp */
        if (remainingToSupplyToPool > 0) {
            supplyBalanceInOf[_cTokenAddress][msg.sender].onPool += remainingToSupplyToPool.div(
                cTokenExchangeRate
            ); // In cToken
            _supplyERC20ToPool(_cTokenAddress, remainingToSupplyToPool); // Revert on error
        }

        _updateSupplierList(_cTokenAddress, msg.sender);
        emit Supplied(msg.sender, _cTokenAddress, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cTokenAddress The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreated(_cTokenAddress)
        isAboveThreshold(_cTokenAddress, _amount)
    {
        _handleMembership(_cTokenAddress, msg.sender);
        _checkAccountLiquidity(msg.sender, _cTokenAddress, 0, _amount);
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        /* DEFAULT CASE: There aren't any borrowers waiting on Comp, Morpho borrows all the tokens from Comp */
        uint256 remainingToBorrowOnPool = _amount;

        /* If some suppliers are waiting on Comp, Morpho matches the borrower in P2P with them as much as possible */
        if (suppliersOnPool[_cTokenAddress].isNotEmpty()) {
            uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
            remainingToBorrowOnPool = _matchSuppliers(_cTokenAddress, _amount); // In underlying
            uint256 matched = _amount - remainingToBorrowOnPool;            
            if (matched > 0) {
                borrowBalanceInOf[_cTokenAddress][msg.sender].inP2P += matched.div(p2pExchangeRate); // In p2pUnit
            }
        }

        /* If there aren't enough suppliers waiting on Comp to match all the tokens borrowed, the rest is borrowed from Comp */
        if (remainingToBorrowOnPool > 0) {
            _unmatchTheSupplier(msg.sender); // Before borrowing on Comp, we put all the collateral of the borrower on Comp (cf Liquidation Invariant in docs)
            require(cToken.borrow(remainingToBorrowOnPool) == 0, "borrow-comp-fail");
            borrowBalanceInOf[_cTokenAddress][msg.sender].onPool += remainingToBorrowOnPool.div(
                cToken.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_cTokenAddress, msg.sender);
        underlyingToken.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _cTokenAddress, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _cTokenAddress, uint256 _amount) external nonReentrant {
        _withdraw(_cTokenAddress, _amount, msg.sender, msg.sender);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cTokenAddress, uint256 _amount) external nonReentrant {
        _repay(_cTokenAddress, msg.sender, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _cTokenBorrowedAddress The address of the debt token the liquidator wants to repay.
     *  @param _cTokenCollateralAddress The address of the collateral the liquidator wants to seize.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(
        address _cTokenBorrowedAddress,
        address _cTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        require(_amount > 0, "liquidate:amount=0");
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        require(debtValue > maxDebtValue, "liquidate:debt-value<=max");
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_cTokenBorrowedAddress][_borrower].onPool.mul(
                ICErc20(_cTokenBorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cTokenBorrowedAddress][_borrower].inP2P.mul(
                marketsManagerForCompound.p2pUnitExchangeRate(_cTokenBorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(comptroller.closeFactorMantissa()),
            "liquidate:amount>allowed"
        );

        _repay(_cTokenBorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(_cTokenCollateralAddress);
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_cTokenBorrowedAddress);
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
        ICErc20 cTokenCollateralToken = ICErc20(_cTokenCollateralAddress);

        vars.amountToSeize = _amount
            .mul(vars.priceBorrowedMantissa)
            .mul(comptroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.collateralOnPoolInUnderlying = supplyBalanceInOf[_cTokenCollateralAddress][_borrower]
            .onPool
            .mul(cTokenCollateralToken.exchangeRateStored());
        uint256 totalCollateral = vars.collateralOnPoolInUnderlying +
            supplyBalanceInOf[_cTokenCollateralAddress][_borrower].inP2P.mul(
                marketsManagerForCompound.updateP2pUnitExchangeRate(_cTokenCollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liquidate:to-seize>collateral");
        _withdraw(_cTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender);
    }

    /* Internal */

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     *  @param _holder the user to whom Morpho will withdraw the supply.
     *  @param _receiver The address of the user that will receive the tokens.
     */
    function _withdraw(
        address _cTokenAddress,
        uint256 _amount,
        address _holder,
        address _receiver
    ) internal isMarketCreated(_cTokenAddress) {
        require(_amount > 0, "_withdraw:amount=0");
        _checkAccountLiquidity(_holder, _cTokenAddress, _amount, 0);
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        uint256 cTokenExchangeRate = cToken.exchangeRateCurrent();
        uint256 remainingToWithdraw = _amount;

        /* If user has some tokens waiting on Comp */
        if (supplyBalanceInOf[_cTokenAddress][_holder].onPool > 0) {
            uint256 amountOnPoolInUnderlying = supplyBalanceInOf[_cTokenAddress][_holder]
                .onPool
                .mul(cTokenExchangeRate);
            /* CASE 1: User withdraws less than his Comp supply balance */
            if (_amount <= amountOnPoolInUnderlying) {
                _withdrawERC20FromComp(_cTokenAddress, _amount); // Revert on error
                supplyBalanceInOf[_cTokenAddress][_holder].onPool -= _amount.div(
                        cTokenExchangeRate
                    ); // In cToken
                remainingToWithdraw = 0; // In underlying
            }
            /* CASE 2: User withdraws more than his Comp supply balance */
            else {
                require(cToken.redeem(supplyBalanceInOf[_cTokenAddress][_holder].onPool) == 0, "_withdraw:redeem-comp-fail");
                supplyBalanceInOf[_cTokenAddress][_holder].onPool = 0;
                remainingToWithdraw = _amount - amountOnPoolInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to withdraw (CASE 2), Morpho breaks credit lines and repair them either with other users or with Comp itself */
        if (remainingToWithdraw > 0) {
            uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
            uint256 cTokenContractBalanceInUnderlying = cToken.balanceOf(address(this)).mul(
                cTokenExchangeRate
            );
            /* CASE 1: Other suppliers have enough tokens on Comp to compensate user's position*/
            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                require(
                    _matchSuppliers(_cTokenAddress, remainingToWithdraw) == 0,
                    "_withdraw:_matchSuppliers!=0"
                );
                supplyBalanceInOf[_cTokenAddress][_holder].inP2P -= remainingToWithdraw.div(
                    p2pExchangeRate
                ); // In p2pUnit
            }
            /* CASE 2: Other suppliers don't have enough tokens on Comp. Such scenario is called the Hard-Withdraw */
            else {
                uint256 remaining = _matchSuppliers(
                    _cTokenAddress,
                    cTokenContractBalanceInUnderlying
                );
                supplyBalanceInOf[_cTokenAddress][_holder].inP2P -= remainingToWithdraw.div(
                    p2pExchangeRate
                ); // In p2pUnit
                remainingToWithdraw -= remaining;
                require(
                    _unmatchBorrowers(_cTokenAddress, remainingToWithdraw) == 0, // We break some P2P credit lines the user had with borrowers and fallback on Comp.
                    "_withdraw:_unmatchBorrowers!=0"
                );
            }
        }

        _updateSupplierList(_cTokenAddress, _holder);
        underlyingToken.safeTransfer(_receiver, _amount);
        emit Withdrawn(_holder, _cTokenAddress, _amount);
    }

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved this contract to spend the underlying `_amount`.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrow.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _cTokenAddress,
        address _borrower,
        uint256 _amount
    ) internal isMarketCreated(_cTokenAddress) {
        require(_amount > 0, "_repay:amount=0");
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 remainingToRepay = _amount;

        /* If user is borrowing tokens on Comp */
        if (borrowBalanceInOf[_cTokenAddress][_borrower].onPool > 0) {
            uint256 borrowIndex = cToken.borrowIndex();
            uint256 onPoolInUnderlying = borrowBalanceInOf[_cTokenAddress][_borrower].onPool.mul(
                borrowIndex
            );
            /* CASE 1: User repays less than his Comp borrow balance */
            if (_amount <= onPoolInUnderlying) {
                underlyingToken.safeApprove(_cTokenAddress, _amount);
                cToken.repayBorrow(_amount);
                borrowBalanceInOf[_cTokenAddress][_borrower].onPool -= _amount.div(borrowIndex); // In cdUnit
                remainingToRepay = 0;
            }
            /* CASE 2: User repays more than his Comp borrow balance */
            else {
                underlyingToken.safeApprove(_cTokenAddress, onPoolInUnderlying);
                cToken.repayBorrow(onPoolInUnderlying); // Revert on error
                borrowBalanceInOf[_cTokenAddress][_borrower].onPool = 0;
                remainingToRepay -= onPoolInUnderlying; // In underlying
            }
        }

        /* If there remains some tokens to repay (CASE 2), Morpho breaks credit lines and repair them either with other users or with Comp itself */
        if (remainingToRepay > 0) {
            // No need to update p2pUnitExchangeRate here as it's done in `_checkAccountLiquidity`
            uint256 p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                _cTokenAddress
            );
            uint256 contractBorrowBalanceOnPool = cToken.borrowBalanceCurrent(address(this)); // In underlying
            /* CASE 1: Other borrowers are borrowing enough on Comp to compensate user's position */
            if (remainingToRepay <= contractBorrowBalanceOnPool) {
                _matchBorrowers(_cTokenAddress, remainingToRepay);
                borrowBalanceInOf[_cTokenAddress][_borrower].inP2P -= remainingToRepay.div(
                    p2pExchangeRate
                );
            }
            /* CASE 2: Other borrowers aren't borrowing enough on Comp to compensate user's position */
            else {
                _matchBorrowers(_cTokenAddress, contractBorrowBalanceOnPool);
                borrowBalanceInOf[_cTokenAddress][_borrower].inP2P -= remainingToRepay.div(
                    p2pExchangeRate
                ); // In p2pUnit
                remainingToRepay -= contractBorrowBalanceOnPool;
                require(
                    _unmatchSuppliers(_cTokenAddress, remainingToRepay) == 0, // We break some P2P credit lines the user had with suppliers and fallback on Comp.
                    "_repay:_unmatchSuppliers!=0"
                );
            }
        }

        _updateBorrowerList(_cTokenAddress, _borrower);
        emit Repaid(_borrower, _cTokenAddress, _amount);
    }

    /** @dev Supplies ERC20 tokens to Comp.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyERC20ToPool(address _cTokenAddress, uint256 _amount) internal isAboveCompoundThreshold(_cTokenAddress, _amount) {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        underlyingToken.safeApprove(_cTokenAddress, _amount);
        require(cToken.mint(_amount) == 0, "_supplyERC20ToPool:mint-comp-fail");
    }

    /** @dev Withdraws ERC20 tokens from Comp.
     *  @param _cTokenAddress The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromComp(address _cTokenAddress, uint256 _amount) internal isAboveCompoundThreshold(_cTokenAddress, _amount) {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        require(cToken.redeemUnderlying(_amount) == 0, "_withdrawERC20FromComp:redeem-comp-fail");
    }

    /** @dev Finds liquidity on Comp and matches it in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _cTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMatch The remaining liquidity to search for in underlying.
     */
    function _matchSuppliers(address _cTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        remainingToMatch = _amount; // In underlying
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
        uint256 cTokenExchangeRate = cToken.exchangeRateCurrent();
        (, address account) = suppliersOnPool[_cTokenAddress].getMaximum();

        bool metAccountWithDebtOnPool;
        while (remainingToMatch > 0 && account != address(0)) {
            address tmpAccount;
            // Check if this user is not borrowing on Cream (cf Liquidation Invariant in docs)
            if (!_hasDebtOnPool(account)) {
                uint256 onCream = supplyBalanceInOf[_cTokenAddress][account].onPool; // In cToken
                uint256 toMatch;
                // This is done to prevent rounding errors
                if (onCream.mul(cTokenExchangeRate) <= remainingToMatch) {
                    supplyBalanceInOf[_cTokenAddress][account].onPool = 0;
                    toMatch = onCream.mul(cTokenExchangeRate);
                } else {
                    toMatch = remainingToMatch;
                    supplyBalanceInOf[_cTokenAddress][account].onPool -= toMatch.div(
                        cTokenExchangeRate
                    ); // In cToken
                }
                remainingToMatch -= toMatch;
                supplyBalanceInOf[_cTokenAddress][account].inP2P += toMatch.div(p2pExchangeRate); // In p2pUnit
                _updateSupplierList(_cTokenAddress, account);
                emit SupplierMatched(account, _cTokenAddress, toMatch);
            } else {
                metAccountWithDebtOnPool = true;
                tmpAccount = suppliersOnPool[_cTokenAddress].prev(account);
            }
            account = tmpAccount;
        }
        // Withdraw from Comp
        _withdrawERC20FromComp(_cTokenAddress, _amount - remainingToMatch);
    }

    /** @dev Finds liquidity in peer-to-peer and unmatches it to reconnect Comp.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _cTokenAddress The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchSuppliers(address _cTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        remainingToUnmatch = _amount; // In underlying
        uint256 cTokenExchangeRate = cToken.exchangeRateCurrent();
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
        (, address account) = suppliersInP2P[_cTokenAddress].getMaximum();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = supplyBalanceInOf[_cTokenAddress][account].inP2P; // In cToken
            uint256 toUnmatch = Math.min(inP2P.mul(p2pExchangeRate), remainingToUnmatch); // In underlying
            remainingToUnmatch -= toUnmatch;
            supplyBalanceInOf[_cTokenAddress][account].onPool += toUnmatch.div(cTokenExchangeRate); // In cToken
            supplyBalanceInOf[_cTokenAddress][account].inP2P -= toUnmatch.div(p2pExchangeRate); // In p2pUnit
            _updateSupplierList(_cTokenAddress, account);
            emit SupplierUnmatched(account, _cTokenAddress, toUnmatch);
            (, account) = suppliersInP2P[_cTokenAddress].getMaximum();
        }
        // Supply on Comp
        _supplyERC20ToPool(_cTokenAddress, _amount - remainingToUnmatch);
    }

    /** @dev Finds borrowers on Comp that match the given `_amount` and move them in P2P.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _cTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _matchBorrowers(address _cTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        IERC20 underlyingToken = IERC20(cToken.underlying());
        remainingToMatch = _amount;
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
        uint256 borrowIndex = cToken.borrowIndex();
        (, address account) = borrowersOnPool[_cTokenAddress].getMaximum();

        while (remainingToMatch > 0 && account != address(0)) {
            uint256 onCream = borrowBalanceInOf[_cTokenAddress][account].onPool; // In cToken
            uint256 toMatch;
            if (onCream.mul(borrowIndex) <= remainingToMatch) {
                toMatch = onCream.mul(borrowIndex);
                borrowBalanceInOf[_cTokenAddress][account].onPool = 0;
            } else {
                toMatch = remainingToMatch;
                borrowBalanceInOf[_cTokenAddress][account].onPool -= toMatch.div(borrowIndex);
            }
            remainingToMatch -= toMatch;
            borrowBalanceInOf[_cTokenAddress][account].inP2P += toMatch.div(p2pExchangeRate);
            _updateBorrowerList(_cTokenAddress, account);
            emit BorrowerMatched(account, _cTokenAddress, toMatch);
            (, account) = borrowersOnPool[_cTokenAddress].getMaximum();
        }
        // Repay Comp
        uint256 toRepay = _amount - remainingToMatch;
        underlyingToken.safeApprove(_cTokenAddress, toRepay);
        require(cToken.repayBorrow(toRepay) == 0, "_matchBorrowers:repay-comp-fail");
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and move them to Comp.
     *  @dev Note: p2pUnitExchangeRate must have been updated before calling this function.
     *  @param _cTokenAddress The address of the market on which Morpho wants to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToUnmatch The amount remaining to munmatchatch in underlying.
     */
    function _unmatchBorrowers(address _cTokenAddress, uint256 _amount)
        internal
        returns (uint256 remainingToUnmatch)
    {
        ICErc20 cToken = ICErc20(_cTokenAddress);
        remainingToUnmatch = _amount;
        uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(_cTokenAddress);
        uint256 borrowIndex = cToken.borrowIndex();
        (, address account) = borrowersInP2P[_cTokenAddress].getMaximum();

        while (remainingToUnmatch > 0 && account != address(0)) {
            uint256 inP2P = borrowBalanceInOf[_cTokenAddress][account].inP2P;
            _unmatchTheSupplier(account); // Before borrowing on Comp, we put all the collateral of the borrower on Comp (cf Liquidation Invariant in docs)
            uint256 toUnmatch = Math.min(inP2P.mul(p2pExchangeRate), remainingToUnmatch); // In underlying
            remainingToUnmatch -= toUnmatch;
            borrowBalanceInOf[_cTokenAddress][account].onPool += toUnmatch.div(borrowIndex);
            borrowBalanceInOf[_cTokenAddress][account].inP2P -= toUnmatch.div(p2pExchangeRate);
            _updateBorrowerList(_cTokenAddress, account);
            emit BorrowerUnmatched(account, _cTokenAddress, toUnmatch);
            (, account) = borrowersInP2P[_cTokenAddress].getMaximum();
        }
        // Borrow on Comp
        require(cToken.borrow(_amount - remainingToUnmatch) == 0);
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Comp.
     * @param _account The address of the account to move balance.
     */
    function _unmatchTheSupplier(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cTokenEntered = enteredMarkets[_account][i];
            uint256 inP2P = supplyBalanceInOf[cTokenEntered][_account].inP2P;

            if (inP2P > 0) {
                uint256 p2pExchangeRate = marketsManagerForCompound.p2pUnitExchangeRate(
                    cTokenEntered
                );
                uint256 cTokenExchangeRate = ICErc20(cTokenEntered).exchangeRateCurrent();
                uint256 inP2PInUnderlying = inP2P.mul(p2pExchangeRate);
                supplyBalanceInOf[cTokenEntered][_account].onPool += inP2PInUnderlying.div(
                    cTokenExchangeRate
                ); // In cToken
                supplyBalanceInOf[cTokenEntered][_account].inP2P -= inP2PInUnderlying.div(
                    p2pExchangeRate
                ); // In p2pUnit
                _unmatchBorrowers(cTokenEntered, inP2PInUnderlying);
                _updateSupplierList(cTokenEntered, _account);
                // Supply to Comp
                _supplyERC20ToPool(cTokenEntered, inP2PInUnderlying);
                emit SupplierUnmatched(_account, cTokenEntered, inP2PInUnderlying);
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
     *  @param _cTokenAddress The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     */
    function _checkAccountLiquidity(
        address _account,
        address _cTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _account,
            _cTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        require(debtValue < maxDebtValue, "_checkAccountLiquidity:debt-value>max");
    }

    /** @dev Returns the debt value, max debt value and collateral value of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _cTokenAddress The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtValue, maxDebtValue collateralValue).
     */
    function _getUserHypotheticalBalanceStates(
        address _account,
        address _cTokenAddress,
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
        BalanceStateVars memory vars;
        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            vars.cTokenEntered = enteredMarkets[_account][i];
            vars.p2pExchangeRate = marketsManagerForCompound.updateP2pUnitExchangeRate(
                vars.cTokenEntered
            );
            // Calculation of the current debt (in underlying)
            vars.debtToAdd =
                borrowBalanceInOf[vars.cTokenEntered][_account].onPool.mul(
                    ICErc20(vars.cTokenEntered).borrowIndex()
                ) +
                borrowBalanceInOf[vars.cTokenEntered][_account].inP2P.mul(vars.p2pExchangeRate);
            // Calculation of the current collateral (in underlying)
            vars.collateralToAdd =
                supplyBalanceInOf[vars.cTokenEntered][_account].onPool.mul(
                    ICErc20(vars.cTokenEntered).exchangeRateCurrent()
                ) +
                supplyBalanceInOf[vars.cTokenEntered][_account].inP2P.mul(vars.p2pExchangeRate);
            // Price recovery
            vars.underlyingPrice = compoundOracle.getUnderlyingPrice(vars.cTokenEntered);
            require(vars.underlyingPrice != 0, "_getUserHypotheticalBalanceStates:oracle-fail");

            if (_cTokenAddress == vars.cTokenEntered) {
                vars.debtToAdd += _borrowedAmount;
                vars.redeemedValue = _withdrawnAmount.mul(vars.underlyingPrice);
            }
            // Conversion of the collateral to dollars
            vars.collateralToAdd = vars.collateralToAdd.mul(vars.underlyingPrice);
            // Add the debt in this market to the global debt (in dollars)
            vars.debtValue += vars.debtToAdd.mul(vars.underlyingPrice);
            // Add the collateral value in this asset to the global collateral value (in dollars)
            vars.collateralValue += vars.collateralToAdd;
            (, uint256 collateralFactorMantissa, ) = comptroller.markets(vars.cTokenEntered);
            // Add the max debt value allowed by the collateral in this asset to the global max debt value (in dollars)
            vars.maxDebtValue += vars.collateralToAdd.mul(collateralFactorMantissa);
        }

        vars.collateralValue -= vars.redeemedValue;

        return (vars.debtValue, vars.maxDebtValue, vars.collateralValue);
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _cTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function _updateBorrowerList(address _cTokenAddress, address _account) internal {
        uint256 onPool = borrowBalanceInOf[_cTokenAddress][_account].onPool;
        uint256 inP2P = borrowBalanceInOf[_cTokenAddress][_account].inP2P;
        uint256 numberOfBorrowersOnPool = borrowersOnPool[_cTokenAddress].numberOfKeys();
        uint256 numberOfBorrowersInP2P = borrowersInP2P[_cTokenAddress].numberOfKeys();
        bool isOnPool = borrowersOnPool[_cTokenAddress].keyExists(_account);
        bool isInP2P = borrowersInP2P[_cTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            borrowersOnPool[_cTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) borrowersOnPool[_cTokenAddress].remove(_account);
        if (onPool > 0 && ((isOnPoolAndValueChanged) || !isOnPool)) {
            if (numberOfBorrowersOnPool <= NMAX) {
                numberOfBorrowersOnPool++;
                borrowersOnPool[_cTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersOnPool[_cTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    borrowersOnPool[_cTokenAddress].remove(minimumAccount);
                    borrowersOnPoolBuffer[_cTokenAddress].add(minimumAccount);
                    borrowersOnPool[_cTokenAddress].insert(_account, onPool);
                } else borrowersOnPoolBuffer[_cTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && borrowersOnPoolBuffer[_cTokenAddress].contains(_account))
            borrowersOnPoolBuffer[_cTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            borrowersInP2P[_cTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) borrowersInP2P[_cTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfBorrowersInP2P <= NMAX) {
                numberOfBorrowersInP2P++;
                borrowersInP2P[_cTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersInP2P[_cTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    borrowersInP2P[_cTokenAddress].remove(minimumAccount);
                    borrowersInP2PBuffer[_cTokenAddress].add(minimumAccount);
                    borrowersInP2P[_cTokenAddress].insert(_account, inP2P);
                } else borrowersInP2PBuffer[_cTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && borrowersInP2PBuffer[_cTokenAddress].contains(_account))
            borrowersInP2PBuffer[_cTokenAddress].remove(_account);

        // Add user to the tree if possible
        if (borrowersOnPoolBuffer[_cTokenAddress].length() > 0 && numberOfBorrowersOnPool <= NMAX) {
            address account = borrowersOnPoolBuffer[_cTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_cTokenAddress][account].onPool;
            borrowersOnPoolBuffer[_cTokenAddress].remove(account);
            borrowersOnPool[_cTokenAddress].insert(account, value);
        }

        // Check P2P
        if (borrowersInP2PBuffer[_cTokenAddress].length() > 0 && numberOfBorrowersInP2P <= NMAX) {
            address account = borrowersInP2PBuffer[_cTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_cTokenAddress][account].inP2P;
            borrowersInP2PBuffer[_cTokenAddress].remove(account);
            borrowersInP2P[_cTokenAddress].insert(account, value);
        }
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _cTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function _updateSupplierList(address _cTokenAddress, address _account) internal {
        uint256 onPool = supplyBalanceInOf[_cTokenAddress][_account].onPool;
        uint256 inP2P = supplyBalanceInOf[_cTokenAddress][_account].inP2P;
        uint256 numberOfSuppliersOnPool = suppliersOnPool[_cTokenAddress].numberOfKeys();
        uint256 numberOfSuppliersInP2P = suppliersInP2P[_cTokenAddress].numberOfKeys();
        bool isOnPool = suppliersOnPool[_cTokenAddress].keyExists(_account);
        bool isInP2P = suppliersInP2P[_cTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            suppliersOnPool[_cTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) suppliersOnPool[_cTokenAddress].remove(_account);
        if (onPool > 0 && (isOnPoolAndValueChanged || !isOnPool)) {
            if (numberOfSuppliersOnPool <= NMAX) {
                numberOfSuppliersOnPool++;
                suppliersOnPool[_cTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersOnPool[_cTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    suppliersOnPool[_cTokenAddress].remove(minimumAccount);
                    suppliersOnPoolBuffer[_cTokenAddress].add(minimumAccount);
                    suppliersOnPool[_cTokenAddress].insert(_account, onPool);
                } else suppliersOnPoolBuffer[_cTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && suppliersOnPoolBuffer[_cTokenAddress].contains(_account))
            suppliersOnPoolBuffer[_cTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            suppliersInP2P[_cTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) suppliersInP2P[_cTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfSuppliersInP2P <= NMAX) {
                numberOfSuppliersInP2P++;
                suppliersInP2P[_cTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersInP2P[_cTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    suppliersInP2P[_cTokenAddress].remove(minimumAccount);
                    suppliersInP2PBuffer[_cTokenAddress].add(minimumAccount);
                    suppliersInP2P[_cTokenAddress].insert(_account, inP2P);
                } else suppliersInP2PBuffer[_cTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && suppliersInP2PBuffer[_cTokenAddress].contains(_account))
            suppliersInP2PBuffer[_cTokenAddress].remove(_account);

        // Add user to the tree if possible
        if (suppliersOnPoolBuffer[_cTokenAddress].length() > 0 && numberOfSuppliersOnPool <= NMAX) {
            address account = suppliersOnPoolBuffer[_cTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_cTokenAddress][account].onPool;
            suppliersOnPoolBuffer[_cTokenAddress].remove(account);
            suppliersOnPool[_cTokenAddress].insert(account, value);
        }
        if (suppliersInP2PBuffer[_cTokenAddress].length() > 0 && numberOfSuppliersInP2P <= NMAX) {
            address account = suppliersInP2PBuffer[_cTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_cTokenAddress][account].inP2P;
            suppliersInP2PBuffer[_cTokenAddress].remove(account);
            suppliersInP2P[_cTokenAddress].insert(account, value);
        }
    }

    function _hasDebtOnPool(address _account) internal view returns (bool) {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            if (borrowBalanceInOf[enteredMarkets[_account][i]][_account].onPool > 0) {
                return true;
            }
        }
        return false;
    }
}
