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
 *  @title CompPositionsManager
 *  @dev Smart contracts interacting with Compound to enable real P2P supply with cERC20 tokens as supply/borrow assets.
 */
contract CompPositionsManager is ReentrancyGuard {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In mUnit (a unit that grows in value, to keep track of the debt increase).
        uint256 onComp; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In mUnit.
        uint256 onComp; // In cdUnit. (a unit that grows in value, to keep track of the  debt increase). Multiply by current borrowIndex to get the underlying amount.
    }

    // Struct to avoid stack too deep error
    struct BalanceState {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 collateralValue; // The collateral value (in USD).
        uint256 withdrawnValue; // The withdrawn value if any (in USD).
    }

    // Struct to avoid stack too deep error
    struct BalanceStateVars {
        uint256 debtToAdd;
        uint256 collateralToAdd;
        uint256 mExchangeRate;
        uint256 underlyingPrice;
        address cERC20Entered;
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

    mapping(address => RedBlackBinaryTree.Tree) public suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) public suppliersOnComp; // Suppliers on Compound.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) public borrowersOnComp; // Borrowers on Compound.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;
    ICompMarketsManager public compMarketsManager;

    /* Events */

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _cERC20Address The address of the market where assets are deposited into.
     *  @param _amount The amount of assets.
     */
    event Deposited(address indexed _account, address indexed _cERC20Address, uint256 _amount);

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

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _cERC20Address The address of the market where assets are deposited.
     *  @param _amount The amount of assets.
     */
    event Repaid(address indexed _account, address indexed _cERC20Address, uint256 _amount);

    /** @dev Emitted when a supplier position is moved from Morpho to Compound.
     *  @param _account The address of the supplier.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromMorphoToComp(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a supplier position is moved from Compound to Morpho.
     *  @param _account The address of the supplier.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event SupplierMovedFromCompToMorpho(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Morpho to Compound.
     *  @param _account The address of the borrower.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromMorphoToComp(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /** @dev Emitted when a borrower position is moved from Compound to Morpho.
     *  @param _account The address of the borrower.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event BorrowerMovedFromCompToMorpho(
        address indexed _account,
        address indexed _cERC20Address,
        uint256 _amount
    );

    /* Modifiers */

    /** @dev Prevents a user to access a market not listed.
     *  @param _cERC20Address The address of the market.
     */
    modifier isMarketListed(address _cERC20Address) {
        require(compMarketsManager.isListed(_cERC20Address), "mkt-not-listed");
        _;
    }

    /** @dev Prevents a user to deposit or borrow less than threshold.
     *  @param _cERC20Address The address of the market.
     *  @param _amount The amount in ERC20 tokens.
     */
    modifier isAboveThreshold(address _cERC20Address, uint256 _amount) {
        require(_amount >= compMarketsManager.thresholds(_cERC20Address), "amount<threshold");
        _;
    }

    /* Constructor */

    constructor(ICompMarketsManager _compMarketsManager, address _proxyComptrollerAddress) {
        compMarketsManager = _compMarketsManager;
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /* External */

    /** @dev Enters Compound's markets.
     *  @param markets The address of the market the user wants to deposit.
     *  @return The results of entered.
     */
    function createMarkets(address[] memory markets) external returns (uint256[] memory) {
        require(msg.sender == address(compMarketsManager), "enter-mkt:only-mkt-manager");
        return comptroller.enterMarkets(markets);
    }

    /** @dev Sets the comptroller and oracle address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external {
        require(msg.sender == address(compMarketsManager), "set-comp:only-mkt-manager");
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /** @dev Deposits ERC20 tokens in a specific market.
     *  @param _cERC20Address The address of the market the user wants to deposit.
     *  @param _amount The amount to deposit in ERC20 tokens.
     */
    function deposit(address _cERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cERC20Address)
        isAboveThreshold(_cERC20Address, _amount)
    {
        _handleMembership(_cERC20Address, msg.sender);
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();

        // If some borrowers are on Compound, Morpho must move them to Morpho
        if (borrowersOnComp[_cERC20Address].isNotEmpty()) {
            uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cERC20Address);
            // Find borrowers and move them to Morpho
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToP2P(_cERC20Address, _amount); // In underlying

            uint256 toRepay = _amount - remainingToSupplyToComp;
            // Update supplier P2P balance
            supplyBalanceInOf[_cERC20Address][msg.sender].inP2P += toRepay.div(mExchangeRate); // In mUnit
            // Repay Compound on behalf of the borrowers with the user deposit
            erc20Token.safeApprove(_cERC20Address, toRepay);
            cERC20Token.repayBorrow(toRepay);

            // If the borrowers on Compound were not sufficient to match all the supply, Morpho put the remaining liquidity on Compound
            if (remainingToSupplyToComp > 0) {
                supplyBalanceInOf[_cERC20Address][msg.sender].onComp += remainingToSupplyToComp.div(
                    cExchangeRate
                ); // In cToken
                _supplyERC20ToComp(_cERC20Address, remainingToSupplyToComp); // Revert on error
            }
        } else {
            // If there is no borrower waiting for a P2P match, Morpho put the user on Compound
            supplyBalanceInOf[_cERC20Address][msg.sender].onComp += _amount.div(cExchangeRate); // In cToken
            _supplyERC20ToComp(_cERC20Address, _amount); // Revert on error
        }

        _updateSupplierList(_cERC20Address, msg.sender);
        emit Deposited(msg.sender, _cERC20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cERC20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cERC20Address)
        isAboveThreshold(_cERC20Address, _amount)
    {
        _handleMembership(_cERC20Address, msg.sender);
        _checkAccountLiquidity(msg.sender, _cERC20Address, 0, _amount);
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cERC20Address);

        // If some suppliers are on Compound, Morpho must pull them out and match them in P2P
        if (suppliersOnComp[_cERC20Address].isNotEmpty()) {
            uint256 remainingToBorrowOnComp = _moveSuppliersFromCompToP2P(_cERC20Address, _amount); // In underlying
            uint256 toWithdraw = _amount - remainingToBorrowOnComp;

            if (toWithdraw > 0) {
                borrowBalanceInOf[_cERC20Address][msg.sender].inP2P += toWithdraw.div(
                    mExchangeRate
                ); // In mUnit
                _withdrawERC20FromComp(_cERC20Address, toWithdraw); // Revert on error
            }

            // If not enough cTokens in peer-to-peer, Morpho must borrow it on Compound
            if (remainingToBorrowOnComp > 0) {
                require(cERC20Token.borrow(remainingToBorrowOnComp) == 0, "bor:borrow-comp-fail");
                borrowBalanceInOf[_cERC20Address][msg.sender].onComp += remainingToBorrowOnComp.div(
                    cERC20Token.borrowIndex()
                ); // In cdUnit
            }
        } else {
            // There is not enough suppliers to provide this borrower demand
            // So Morpho put all of its collateral on Compound, and borrow on Compound for him
            _moveSupplierFromP2PToComp(msg.sender);
            require(cERC20Token.borrow(_amount) == 0, "bor:borrow-comp-fail");
            borrowBalanceInOf[_cERC20Address][msg.sender].onComp += _amount.div(
                cERC20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_cERC20Address, msg.sender);
        // Transfer ERC20 tokens to borrower
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrowed(msg.sender, _cERC20Address, _amount);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cERC20Address, uint256 _amount) external nonReentrant {
        _repay(_cERC20Address, msg.sender, _amount);
    }

    /** @dev Withdraws ERC20 tokens from supply.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from supply.
     */
    function withdraw(address _cERC20Address, uint256 _amount)
        external
        nonReentrant
        isMarketListed(_cERC20Address)
    {
        require(_amount > 0, "red:amount=0");
        _checkAccountLiquidity(msg.sender, _cERC20Address, _amount, 0);

        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());

        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cERC20Address);
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = supplyBalanceInOf[_cERC20Address][msg.sender].onComp.mul(
            cExchangeRate
        );

        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where Morpho can directly withdraw unused liquidity from Compound
            supplyBalanceInOf[_cERC20Address][msg.sender].onComp -= _amount.div(cExchangeRate); // In cToken
            _withdrawERC20FromComp(_cERC20Address, _amount); // Revert on error
        } else {
            // First, Morpho take all the unused liquidy of the user on Compound
            _withdrawERC20FromComp(_cERC20Address, amountOnCompInUnderlying); // Revert on error
            supplyBalanceInOf[_cERC20Address][msg.sender].onComp -= amountOnCompInUnderlying.div(
                cExchangeRate
            );
            // Then, search for the remaining liquidity in peer-to-peer
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying
            supplyBalanceInOf[_cERC20Address][msg.sender].inP2P -= remainingToWithdraw.div(
                mExchangeRate
            ); // In mUnit
            uint256 cTokenContractBalanceInUnderlying = cERC20Token.balanceOf(address(this)).mul(
                cExchangeRate
            );

            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough unused liquidity in peer-to-peer, so Morpho reconnect the credit lines to others suppliers
                require(
                    _moveSuppliersFromCompToP2P(_cERC20Address, remainingToWithdraw) == 0,
                    "red:remaining-suppliers!=0"
                );
                _withdrawERC20FromComp(_cERC20Address, remainingToWithdraw); // Revert on error
            } else {
                // The contract does not have enough cTokens for the withdraw
                // First, Morpho use all the available cTokens in the contract
                uint256 toWithdraw = cTokenContractBalanceInUnderlying -
                    _moveSuppliersFromCompToP2P(_cERC20Address, cTokenContractBalanceInUnderlying); // The amount that can be withdrawn for underlying
                // Update the remaining amount to withdraw to `msg.sender`
                remainingToWithdraw -= toWithdraw;
                _withdrawERC20FromComp(_cERC20Address, toWithdraw); // Revert on error
                // Then, Morpho move borrowers not matched anymore from Morpho to Compound and borrow the amount directly on Compound, thanks to their collateral which is now on Compound
                require(
                    _moveBorrowersFromP2PToComp(_cERC20Address, remainingToWithdraw) == 0,
                    "red:remaining-borrowers!=0"
                );
                require(cERC20Token.borrow(remainingToWithdraw) == 0, "red:borrow-comp-fail");
            }
        }

        _updateSupplierList(_cERC20Address, msg.sender);
        // Transfer back the ERC20 tokens
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _cERC20Address, _amount);
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
        require(maxDebtValue > debtValue, "liq:debt-value<=max");
        LiquidateVars memory vars;
        vars.borrowBalance =
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].onComp.mul(
                ICErc20(_cERC20BorrowedAddress).borrowIndex()
            ) +
            borrowBalanceInOf[_cERC20BorrowedAddress][_borrower].inP2P.mul(
                compMarketsManager.mUnitExchangeRate(_cERC20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowBalance.mul(comptroller.closeFactorMantissa()),
            "liq:amount>allowed"
        );

        _repay(_cERC20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(_cERC20CollateralAddress);
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_cERC20BorrowedAddress);
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
            .mul(comptroller.liquidationIncentiveMantissa())
            .div(vars.priceCollateralMantissa);

        vars.onCompInUnderlying = supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onComp.mul(
            cERC20CollateralToken.exchangeRateStored()
        );
        uint256 totalCollateral = vars.onCompInUnderlying +
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P.mul(
                compMarketsManager.updateMUnitExchangeRate(_cERC20CollateralAddress)
            );

        require(vars.amountToSeize <= totalCollateral, "liq:toseize>collateral");

        if (vars.amountToSeize <= vars.onCompInUnderlying) {
            // Seize tokens from Compound
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onComp -= vars.amountToSeize.div(
                cERC20CollateralToken.exchangeRateStored()
            );
            _withdrawERC20FromComp(_cERC20CollateralAddress, vars.amountToSeize);
        } else {
            // Seize tokens from Morpho and Compound
            uint256 toMove = vars.amountToSeize - vars.onCompInUnderlying;
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].inP2P -= toMove.div(
                compMarketsManager.mUnitExchangeRate(_cERC20CollateralAddress)
            );

            // Check balances before and after to avoid round errors issues
            uint256 balanceBefore = erc20CollateralToken.balanceOf(address(this));
            require(
                cERC20CollateralToken.redeem(
                    supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onComp
                ) == 0,
                "liq:withdraw-cToken-fail"
            );
            supplyBalanceInOf[_cERC20CollateralAddress][_borrower].onComp = 0;
            require(cERC20CollateralToken.borrow(toMove) == 0, "liq:borrow-comp-fail");
            uint256 balanceAfter = erc20CollateralToken.balanceOf(address(this));
            vars.amountToSeize = balanceAfter - balanceBefore;
            _moveBorrowersFromP2PToComp(_cERC20CollateralAddress, toMove);
        }

        _updateSupplierList(_cERC20CollateralAddress, _borrower);
        // Transfer ERC20 tokens to liquidator
        erc20CollateralToken.safeTransfer(msg.sender, vars.amountToSeize);
    }

    /* Internal */

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
    ) internal isMarketListed(_cERC20Address) {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        IERC20 erc20Token = IERC20(cERC20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cERC20Address);

        if (borrowBalanceInOf[_cERC20Address][_borrower].onComp > 0) {
            uint256 onCompInUnderlying = borrowBalanceInOf[_cERC20Address][_borrower].onComp.mul(
                cERC20Token.borrowIndex()
            );

            if (_amount <= onCompInUnderlying) {
                borrowBalanceInOf[_cERC20Address][_borrower].onComp -= _amount.div(
                    cERC20Token.borrowIndex()
                ); // In cdUnit
                // Repay Compound
                erc20Token.safeApprove(_cERC20Address, _amount);
                cERC20Token.repayBorrow(_amount);
            } else {
                // Move the remaining liquidity to Compound
                uint256 remainingToSupplyToComp = _amount - onCompInUnderlying; // In underlying
                borrowBalanceInOf[_cERC20Address][_borrower].inP2P -= remainingToSupplyToComp.div(
                    mExchangeRate
                );
                uint256 index = cERC20Token.borrowIndex();
                borrowBalanceInOf[_cERC20Address][_borrower].onComp -= onCompInUnderlying.div(
                    index
                ); // Morpho use a fresh new borrowIndex since the borrowIndex is updated after a repay

                require(
                    _moveSuppliersFromP2PToComp(_cERC20Address, remainingToSupplyToComp) == 0,
                    "_rep(1):remaining-suppliers!=0"
                );

                // Repay Compound
                erc20Token.safeApprove(_cERC20Address, onCompInUnderlying);
                cERC20Token.repayBorrow(onCompInUnderlying); // Revert on error

                if (remainingToSupplyToComp > 0)
                    _supplyERC20ToComp(_cERC20Address, remainingToSupplyToComp);
            }
        } else {
            borrowBalanceInOf[_cERC20Address][_borrower].inP2P -= _amount.div(mExchangeRate); // In mUnit
            require(
                _moveSuppliersFromP2PToComp(_cERC20Address, _amount) == 0,
                "_rep(2):remaining-suppliers!=0"
            );
            _supplyERC20ToComp(_cERC20Address, _amount);
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
        // Approve transfer on the ERC20 contract
        erc20Token.safeApprove(_cERC20Address, _amount);
        // Mint cTokens
        require(cERC20Token.mint(_amount) == 0, "_supp-to-comp:cToken-mint-fail");
    }

    /** @dev Withdraws ERC20 tokens from Compound.
     *  @param _cERC20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be withdrawn.
     */
    function _withdrawERC20FromComp(address _cERC20Address, uint256 _amount) internal {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        require(
            cERC20Token.redeemUnderlying(_amount) == 0,
            "_withdraw-from-comp:withdraw-comp-fail"
        );
    }

    /** @dev Finds liquidity on Compound and moves it to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @return remainingToMove The remaining liquidity to search for in underlying.
     */
    function _moveSuppliersFromCompToP2P(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToMove = _amount; // In underlying
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cERC20Address);
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 highestValue = suppliersOnComp[_cERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (suppliersOnComp[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersOnComp[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 onComp = supplyBalanceInOf[_cERC20Address][account].onComp; // In cToken

                if (onComp > 0) {
                    uint256 toMove;
                    if (onComp.mul(cExchangeRate) <= remainingToMove) {
                        supplyBalanceInOf[_cERC20Address][account].onComp = 0;
                        toMove = onComp.mul(cExchangeRate);
                    } else {
                        toMove = remainingToMove;
                        supplyBalanceInOf[_cERC20Address][account].onComp -= toMove.div(
                            cExchangeRate
                        ); // In cToken
                    }
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_cERC20Address][account].inP2P += toMove.div(mExchangeRate); // In mUnit

                    _updateSupplierList(_cERC20Address, account);
                    emit SupplierMovedFromCompToMorpho(account, _cERC20Address, toMove);
                }
            }
            highestValue = suppliersOnComp[_cERC20Address].last();
        }
    }

    /** @dev Finds liquidity in peer-to-peer and moves it to Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to search for in underlying.
     */
    function _moveSuppliersFromP2PToComp(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToMove = _amount; // In underlying
        uint256 cExchangeRate = cERC20Token.exchangeRateCurrent();
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cERC20Address);
        uint256 highestValue = suppliersInP2P[_cERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (suppliersInP2P[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = suppliersInP2P[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = supplyBalanceInOf[_cERC20Address][account].inP2P; // In cToken

                if (inP2P > 0) {
                    uint256 toMove = Math.min(inP2P.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    supplyBalanceInOf[_cERC20Address][account].onComp += toMove.div(cExchangeRate); // In cToken
                    supplyBalanceInOf[_cERC20Address][account].inP2P -= toMove.div(mExchangeRate); // In mUnit

                    _updateSupplierList(_cERC20Address, account);
                    emit SupplierMovedFromMorphoToComp(account, _cERC20Address, toMove);
                }
            }
            highestValue = suppliersInP2P[_cERC20Address].last();
        }
    }

    /** @dev Finds borrowers in peer-to-peer that match the given `_amount` and moves them to Compound.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromP2PToComp(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cERC20Address);
        uint256 borrowIndex = cERC20Token.borrowIndex();
        uint256 highestValue = borrowersInP2P[_cERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersInP2P[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersInP2P[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 inP2P = borrowBalanceInOf[_cERC20Address][account].inP2P;

                if (inP2P > 0) {
                    uint256 toMove = Math.min(inP2P.mul(mExchangeRate), remainingToMove); // In underlying
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_cERC20Address][account].onComp += toMove.div(borrowIndex);
                    borrowBalanceInOf[_cERC20Address][account].inP2P -= toMove.div(mExchangeRate);

                    _updateBorrowerList(_cERC20Address, account);
                    emit BorrowerMovedFromMorphoToComp(account, _cERC20Address, toMove);
                }
            }
            highestValue = borrowersInP2P[_cERC20Address].last();
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @dev Note: mUnitExchangeRate must have been updated before calling this function.
     *  @param _cERC20Address The address of the market on which Morpho want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMove The amount remaining to match in underlying.
     */
    function _moveBorrowersFromCompToP2P(address _cERC20Address, uint256 _amount)
        internal
        returns (uint256 remainingToMove)
    {
        ICErc20 cERC20Token = ICErc20(_cERC20Address);
        remainingToMove = _amount;
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cERC20Address);
        uint256 borrowIndex = cERC20Token.borrowIndex();
        uint256 highestValue = borrowersOnComp[_cERC20Address].last();

        while (remainingToMove > 0 && highestValue != 0) {
            while (borrowersOnComp[_cERC20Address].getNumberOfKeysAtValue(highestValue) > 0) {
                address account = borrowersOnComp[_cERC20Address].valueKeyAtIndex(highestValue, 0);
                uint256 onComp = borrowBalanceInOf[_cERC20Address][account].onComp; // In cToken

                if (onComp > 0) {
                    uint256 toMove;
                    if (onComp.mul(borrowIndex) <= remainingToMove) {
                        toMove = onComp.mul(borrowIndex);
                        borrowBalanceInOf[_cERC20Address][account].onComp = 0;
                    } else {
                        toMove = remainingToMove;
                        borrowBalanceInOf[_cERC20Address][account].onComp -= toMove.div(
                            borrowIndex
                        );
                    }
                    remainingToMove -= toMove;
                    borrowBalanceInOf[_cERC20Address][account].inP2P += toMove.div(mExchangeRate);

                    _updateBorrowerList(_cERC20Address, account);
                    emit BorrowerMovedFromCompToMorpho(account, _cERC20Address, toMove);
                }
            }
            highestValue = borrowersOnComp[_cERC20Address].last();
        }
    }

    /**
     * @dev Moves supply balance of an account from Morpho to Compound.
     * @param _account The address of the account to move balance.
     */
    function _moveSupplierFromP2PToComp(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cERC20Entered = enteredMarkets[_account][i];
            uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(cERC20Entered);
            uint256 cExchangeRate = ICErc20(cERC20Entered).exchangeRateCurrent();
            uint256 inP2PInUnderlying = supplyBalanceInOf[cERC20Entered][_account].inP2P.mul(
                mExchangeRate
            );

            if (inP2PInUnderlying > 0) {
                supplyBalanceInOf[cERC20Entered][_account].onComp += inP2PInUnderlying.div(
                    cExchangeRate
                ); // In cToken
                supplyBalanceInOf[cERC20Entered][_account].inP2P -= inP2PInUnderlying.div(
                    mExchangeRate
                ); // In mUnit

                _moveBorrowersFromP2PToComp(cERC20Entered, inP2PInUnderlying);
                _updateSupplierList(cERC20Entered, _account);
                emit SupplierMovedFromMorphoToComp(_account, cERC20Entered, inP2PInUnderlying);
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
        require(debtValue < maxDebtValue, "debt-value>max");
    }

    /** @dev Returns the debt price, max debt price and collateral price of a given user.
     *  @param _account The user to determine liquidity for.
     *  @param _cERC20Address The market to hypothetically withdraw/borrow in.
     *  @param _withdrawnAmount The number of tokens to hypothetically withdraw.
     *  @param _borrowedAmount The amount of underlying to hypothetically borrow.
     *  @return (debtPrice, maxDebtPrice, collateralPrice).
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
        BalanceState memory balanceState;

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            // Avoid stack too deep error
            BalanceStateVars memory vars;
            vars.cERC20Entered = enteredMarkets[_account][i];
            vars.mExchangeRate = compMarketsManager.updateMUnitExchangeRate(vars.cERC20Entered);
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
            if (_cERC20Address == vars.cERC20Entered) {
                vars.debtToAdd += _borrowedAmount;
                balanceState.withdrawnValue = _withdrawnAmount.mul(vars.underlyingPrice);
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

        balanceState.collateralValue -= balanceState.withdrawnValue;

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
        if (borrowBalanceInOf[_cERC20Address][_account].onComp > 0) {
            borrowersOnComp[_cERC20Address].insert(
                _account,
                borrowBalanceInOf[_cERC20Address][_account].onComp
            );
        }
        if (borrowBalanceInOf[_cERC20Address][_account].inP2P > 0) {
            borrowersInP2P[_cERC20Address].insert(
                _account,
                borrowBalanceInOf[_cERC20Address][_account].inP2P
            );
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
        if (supplyBalanceInOf[_cERC20Address][_account].onComp > 0) {
            suppliersOnComp[_cERC20Address].insert(
                _account,
                supplyBalanceInOf[_cERC20Address][_account].onComp
            );
        }
        if (supplyBalanceInOf[_cERC20Address][_account].inP2P > 0) {
            suppliersInP2P[_cERC20Address].insert(
                _account,
                supplyBalanceInOf[_cERC20Address][_account].inP2P
            );
        }
    }
}
