// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import "./libraries/DoubleLinkedList.sol";
import "./interfaces/ICompMarketsManager.sol";
import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CompPositionsManager
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with cERC20 tokens as lending/borrowing assets.
 */
contract CompPositionsManager is ReentrancyGuard {
    using DoubleLinkedList for DoubleLinkedList.List;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct LendingBalance {
        uint256 onMorpho; // In mUnit (a unit that grows in value, to keep track of the debt increase).
        uint256 onComp; // In cToken.
    }

    struct BorrowingBalance {
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
        uint256 borrowingBalance;
        uint256 priceCollateralMantissa;
        uint256 priceBorrowedMantissa;
        uint256 amountToSeize;
        uint256 onCompInUnderlying;
    }

    /* Storage */

    mapping(address => DoubleLinkedList.List) public lendersOnMorpho; // Lenders on Morpho.
    mapping(address => DoubleLinkedList.List) public lendersOnComp; // Lenders on Compound.
    mapping(address => DoubleLinkedList.List) public borrowersOnMorpho; // Borrowers on Morpho.
    mapping(address => DoubleLinkedList.List) public borrowersOnComp; // Borrowers on Compound.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => mapping(address => LendingBalance)) public lendingBalanceInOf; // Lending balance of user.
    mapping(address => mapping(address => BorrowingBalance)) public borrowingBalanceInOf; // Borrowing balance of user.
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
    event Deposit(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a redeem happens.
     *  @param _account The address of the redeemer.
     *  @param _cErc20Address The address of the market from where assets are redeemed.
     *  @param _amount The amount of assets.
     */
    event Redeem(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a borrow happens.
     *  @param _account The address of the borrower.
     *  @param _cErc20Address The address of the market where assets are borrowed.
     *  @param _amount The amount of assets.
     */
    event Borrow(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a deposit happens.
     *  @param _account The address of the depositor.
     *  @param _cErc20Address The address of the market where assets are deposited.
     *  @param _amount The amount of assets.
     */
    event Repay(address indexed _account, address indexed _cErc20Address, uint256 _amount);

    /** @dev Emitted when a lender position is moved from Morpho to Compound.
     *  @param _account The address of the lender.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event LenderMovedFromMorphoToComp(
        address indexed _account,
        address indexed _cErc20Address,
        uint256 _amount
    );

    /** @dev Emitted when a lender position is moved from Compound to Morpho.
     *  @param _account The address of the lender.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount of assets.
     */
    event LenderMovedFromCompToMorpho(
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
    function enterMarkets(address[] memory markets) external returns (uint256[] memory) {
        require(msg.sender == address(compMarketsManager), "enterMarkets: only Morpho");
        return comptroller.enterMarkets(markets);
    }

    /** @dev Sets the comptroller and oracle address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external {
        require(msg.sender == address(compMarketsManager), "enterMarkets: only compMarketsManager");
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundOracle = ICompoundOracle(comptroller.oracle());
    }

    /** @dev Deposits ERC20 tokens in a specific market.
     *  @param _cErc20Address The address of the market the user wants to deposit.
     *  @param _amount The amount to deposit in ERC20 tokens.
     */
    function deposit(address _cErc20Address, uint256 _amount) external nonReentrant {
        require(
            _amount >=
                compMarketsManager.thresholds(
                    _cErc20Address,
                    ICompMarketsManager.Threshold.Underlying
                ),
            "deposit: amount cannot be less than THRESHOLD"
        );
        require(compMarketsManager.isListed(_cErc20Address), "deposit: market not listed");

        _handleMembership(_cErc20Address, msg.sender);
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();

        // If some borrowers are on Compound, we must move them to Morpho
        if (borrowersOnComp[_cErc20Address].length() > 0) {
            uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);
            // Find borrowers and move them to Morpho
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                _cErc20Address,
                _amount
            ); // In underlying

            // Repay Compound
            uint256 toRepay = _amount - remainingToSupplyToComp;
            // Update lender balance
            lendingBalanceInOf[_cErc20Address][msg.sender].onMorpho += toRepay.div(mExchangeRate); // In mUnit
            erc20Token.safeApprove(_cErc20Address, toRepay);
            cErc20Token.repayBorrow(toRepay);

            if (remainingToSupplyToComp > 0) {
                lendingBalanceInOf[_cErc20Address][msg.sender].onComp += remainingToSupplyToComp
                    .div(cExchangeRate); // In cToken
                _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp); // Revert on error
            }
        } else {
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp += _amount.div(cExchangeRate); // In cToken
            _supplyErc20ToComp(_cErc20Address, _amount); // Revert on error
        }

        _updateLenderList(_cErc20Address, msg.sender);
        emit Deposit(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cErc20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cErc20Address, uint256 _amount) external nonReentrant {
        _handleMembership(_cErc20Address, msg.sender);
        require(compMarketsManager.isListed(_cErc20Address), "borrow: market not listed");
        require(
            _amount >=
                compMarketsManager.thresholds(
                    _cErc20Address,
                    ICompMarketsManager.Threshold.Underlying
                ),
            "borrow: amount cannot be less than THRESHOLD"
        );
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalStateBalances(
            msg.sender,
            _cErc20Address,
            0,
            _amount
        );
        require(debtValue < maxDebtValue, "borrow: debt value exceeds max");

        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);

        // If some lenders are on Compound, we must move them to Morpho
        if (lendersOnComp[_cErc20Address].length() > 0) {
            uint256 remainingToBorrowOnComp = _moveLendersFromCompToMorpho(
                _cErc20Address,
                _amount,
                msg.sender
            ); // In underlying
            uint256 toRedeem = _amount - remainingToBorrowOnComp;

            if (toRedeem > 0) {
                borrowingBalanceInOf[_cErc20Address][msg.sender].onMorpho += toRedeem.div(
                    mExchangeRate
                ); // In mUnit
                _redeemErc20FromComp(_cErc20Address, toRedeem); // Revert on error
            }

            // If not enough cTokens on Morpho, we must borrow it on Compound
            if (remainingToBorrowOnComp > 0) {
                require(
                    cErc20Token.borrow(remainingToBorrowOnComp) == 0,
                    "borrow: borrow on Compound failed"
                );
                borrowingBalanceInOf[_cErc20Address][msg.sender].onComp += remainingToBorrowOnComp
                    .div(cErc20Token.borrowIndex()); // In cdUnit
            }
        } else {
            _moveLenderFromMorphoToComp(msg.sender);
            require(cErc20Token.borrow(_amount) == 0, "borrow: borrow on Compound failed");
            borrowingBalanceInOf[_cErc20Address][msg.sender].onComp += _amount.div(
                cErc20Token.borrowIndex()
            ); // In cdUnit
        }

        _updateBorrowerList(_cErc20Address, msg.sender);
        // Transfer ERC20 tokens to borrower
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cErc20Address, uint256 _amount) external nonReentrant {
        _repay(_cErc20Address, msg.sender, _amount);
    }

    /** @dev Redeems ERC20 tokens from lending.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from lending.
     */
    function redeem(address _cErc20Address, uint256 _amount) external nonReentrant {
        require(_amount > 0, "redeem: amount cannot be 0");
        require(compMarketsManager.isListed(_cErc20Address), "redeem: market not listed");
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalStateBalances(
            msg.sender,
            _cErc20Address,
            _amount,
            0
        );
        require(debtValue < maxDebtValue, "redeem: debt value exceeds max");

        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());

        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = lendingBalanceInOf[_cErc20Address][msg.sender]
            .onComp
            .mul(cExchangeRate);

        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where we can directly withdraw unused liquidity from Compound
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp -= _amount.div(cExchangeRate); // In cToken
            _redeemErc20FromComp(_cErc20Address, _amount); // Revert on error
        } else {
            // First, we take all the unused liquidy on Compound.
            _redeemErc20FromComp(_cErc20Address, amountOnCompInUnderlying); // Revert on error
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp -= amountOnCompInUnderlying.div(
                cExchangeRate
            );
            // Then, search for the remaining liquidity on Morpho
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying
            lendingBalanceInOf[_cErc20Address][msg.sender].onMorpho -= remainingToWithdraw.div(
                mExchangeRate
            ); // In mUnit
            uint256 cTokenContractBalanceInUnderlying = cErc20Token.balanceOf(address(this)).mul(
                cExchangeRate
            );

            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough cTokens in the contract to use
                require(
                    _moveLendersFromCompToMorpho(_cErc20Address, remainingToWithdraw, msg.sender) ==
                        0,
                    "redeem: remaining to move should be 0"
                );
                _redeemErc20FromComp(_cErc20Address, remainingToWithdraw); // Revert on error
            } else {
                // The contract does not have enough cTokens for the withdraw
                // First, we use all the available cTokens in the contract
                uint256 toRedeem = cTokenContractBalanceInUnderlying -
                    _moveLendersFromCompToMorpho(
                        _cErc20Address,
                        cTokenContractBalanceInUnderlying,
                        msg.sender
                    ); // The amount that can be redeemed for underlying
                // Update the remaining amount to withdraw to `msg.sender`
                remainingToWithdraw -= toRedeem;
                _redeemErc20FromComp(_cErc20Address, toRedeem); // Revert on error
                // Then, we move borrowers not matched anymore from Morpho to Compound and borrow the amount directly on Compound
                require(
                    _moveBorrowersFromMorphoToComp(_cErc20Address, remainingToWithdraw) == 0,
                    "redeem: all liquidity should have been moved"
                );
                require(
                    cErc20Token.borrow(remainingToWithdraw) == 0,
                    "redeem: borrow on Compound failed"
                );
            }
        }

        _updateLenderList(_cErc20Address, msg.sender);
        // Transfer back the ERC20 tokens
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Redeem(msg.sender, _cErc20Address, _amount);
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
        require(maxDebtValue > debtValue, "liquidate: debt value is below max");
        LiquidateVars memory vars;
        vars.borrowingBalance =
            borrowingBalanceInOf[_cErc20BorrowedAddress][_borrower].onComp.mul(
                ICErc20(_cErc20BorrowedAddress).borrowIndex()
            ) +
            borrowingBalanceInOf[_cErc20BorrowedAddress][_borrower].onMorpho.mul(
                compMarketsManager.mUnitExchangeRate(_cErc20BorrowedAddress)
            );
        require(
            _amount <= vars.borrowingBalance.mul(comptroller.closeFactorMantissa()),
            "liquidate: cannot repay more than allowed by close factor"
        );

        _repay(_cErc20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        vars.priceCollateralMantissa = compoundOracle.getUnderlyingPrice(_cErc20CollateralAddress);
        vars.priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(_cErc20BorrowedAddress);
        require(
            vars.priceCollateralMantissa != 0 && vars.priceBorrowedMantissa != 0,
            "liquidate: oracle failed"
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

        vars.onCompInUnderlying = lendingBalanceInOf[_cErc20CollateralAddress][_borrower]
            .onComp
            .mul(cErc20CollateralToken.exchangeRateStored());
        uint256 totalCollateral = vars.onCompInUnderlying +
            lendingBalanceInOf[_cErc20CollateralAddress][_borrower].onMorpho.mul(
                compMarketsManager.updateMUnitExchangeRate(_cErc20CollateralAddress)
            );

        require(
            vars.amountToSeize <= totalCollateral,
            "liquidate: cannot seize more than borrower's collateral balance"
        );

        if (vars.amountToSeize <= vars.onCompInUnderlying) {
            // Seize tokens from Compound
            lendingBalanceInOf[_cErc20CollateralAddress][_borrower].onComp -= vars
                .amountToSeize
                .div(cErc20CollateralToken.exchangeRateStored());
            _redeemErc20FromComp(_cErc20CollateralAddress, vars.amountToSeize);
        } else {
            // Seize tokens from Morpho and Compound
            uint256 toMove = vars.amountToSeize - vars.onCompInUnderlying;
            lendingBalanceInOf[_cErc20CollateralAddress][_borrower].onMorpho -= toMove.div(
                compMarketsManager.mUnitExchangeRate(_cErc20CollateralAddress)
            );

            // Check balances before and after to avoid round errors issues
            uint256 balanceBefore = erc20CollateralToken.balanceOf(address(this));
            require(
                cErc20CollateralToken.redeem(
                    lendingBalanceInOf[_cErc20CollateralAddress][_borrower].onComp
                ) == 0,
                "liquidate: redeem cToken on Compound failed"
            );
            lendingBalanceInOf[_cErc20CollateralAddress][_borrower].onComp = 0;
            require(
                cErc20CollateralToken.borrow(toMove) == 0,
                "liquidate: borrow on Compound failed"
            );
            uint256 balanceAfter = erc20CollateralToken.balanceOf(address(this));
            vars.amountToSeize = balanceAfter - balanceBefore;
            _moveBorrowersFromMorphoToComp(_cErc20CollateralAddress, toMove);
        }

        _updateLenderList(_cErc20CollateralAddress, _borrower);
        // Transfer ERC20 tokens to liquidator
        erc20CollateralToken.safeTransfer(msg.sender, vars.amountToSeize);
    }

    /* Internal */

    /** @dev Implements repay logic.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _borrower The address of the `_borrower` to repay the borrowing.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(
        address _cErc20Address,
        address _borrower,
        uint256 _amount
    ) internal {
        require(compMarketsManager.isListed(_cErc20Address), "_repay: market not listed");
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = compMarketsManager.updateMUnitExchangeRate(_cErc20Address);

        if (borrowingBalanceInOf[_cErc20Address][_borrower].onComp > 0) {
            uint256 onCompInUnderlying = borrowingBalanceInOf[_cErc20Address][_borrower].onComp.mul(
                cErc20Token.borrowIndex()
            );

            if (_amount <= onCompInUnderlying) {
                borrowingBalanceInOf[_cErc20Address][_borrower].onComp -= _amount.div(
                    cErc20Token.borrowIndex()
                ); // In cdUnit
                // Repay Compound
                erc20Token.safeApprove(_cErc20Address, _amount);
                cErc20Token.repayBorrow(_amount);
            } else {
                // Move the remaining liquidity to Compound
                uint256 remainingToSupplyToComp = _amount - onCompInUnderlying; // In underlying
                borrowingBalanceInOf[_cErc20Address][_borrower].onMorpho -= remainingToSupplyToComp
                    .div(mExchangeRate);
                uint256 index = cErc20Token.borrowIndex();
                borrowingBalanceInOf[_cErc20Address][_borrower].onComp -= onCompInUnderlying.div(
                    index
                ); // We use a fresh new borrowIndex since the borrowIndex is updated after a repay

                _moveLendersFromMorphoToComp(_cErc20Address, remainingToSupplyToComp, _borrower); // Revert on error

                // Repay Compound
                erc20Token.safeApprove(_cErc20Address, onCompInUnderlying);
                cErc20Token.repayBorrow(onCompInUnderlying); // Revert on error

                if (remainingToSupplyToComp > 0)
                    _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp);
            }
        } else {
            borrowingBalanceInOf[_cErc20Address][_borrower].onMorpho -= _amount.div(mExchangeRate); // In mUnit
            _moveLendersFromMorphoToComp(_cErc20Address, _amount, _borrower);
            _supplyErc20ToComp(_cErc20Address, _amount);
        }

        _updateBorrowerList(_cErc20Address, _borrower);
        emit Repay(_borrower, _cErc20Address, _amount);
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyErc20ToComp(address _cErc20Address, uint256 _amount) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        // Approve transfer on the ERC20 contract
        erc20Token.safeApprove(_cErc20Address, _amount);
        // Mint cTokens
        require(cErc20Token.mint(_amount) == 0, "_supplyErc20ToComp: cToken minting failed");
    }

    /** @dev Redeems ERC20 tokens from Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be redeemed.
     */
    function _redeemErc20FromComp(address _cErc20Address, uint256 _amount) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        require(
            cErc20Token.redeemUnderlying(_amount) == 0,
            "_redeemErc20FromComp: redeem ERC20 on Compound failed"
        );
    }

    /** @dev Finds liquidity on Compound and moves it to Morpho.
     *  @dev Note: mUnitExchangeRate must have been upated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     *  @return remainingToMove The remaining liquidity to search for in underlying.
     */
    function _moveLendersFromCompToMorpho(
        address _cErc20Address,
        uint256 _amount,
        address _lenderToAvoid
    ) internal returns (uint256 remainingToMove) {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMove = _amount; // In underlying
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 length = lendersOnComp[_cErc20Address].length();
        address lender = lendersOnComp[_cErc20Address].getHead();
        uint256 i;

        while (remainingToMove > 0 && i < length) {
            if (lender != _lenderToAvoid) {
                uint256 onComp = lendingBalanceInOf[_cErc20Address][lender].onComp; // In cToken

                if (onComp > 0) {
                    uint256 toMove; // In underlying
                    if (onComp.mul(cExchangeRate) <= remainingToMove) {
                        toMove = onComp.mul(cExchangeRate);
                        lendingBalanceInOf[_cErc20Address][lender].onComp = 0;
                    } else {
                        toMove = remainingToMove;
                        lendingBalanceInOf[_cErc20Address][lender].onComp -= toMove.div(
                            cExchangeRate
                        );
                    }
                    remainingToMove -= toMove;
                    lendingBalanceInOf[_cErc20Address][lender].onMorpho += toMove.div(
                        mExchangeRate
                    ); // In mUnit

                    _updateLenderList(_cErc20Address, lender);
                    emit LenderMovedFromCompToMorpho(lender, _cErc20Address, toMove);
                }

                lender = lendersOnComp[_cErc20Address].getHead();
            } else {
                lender = lendersOnComp[_cErc20Address].getNext(lender);
            }

            i++;
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @dev Note: mUnitExchangeRate must have been upated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to search for in underlying.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     */
    function _moveLendersFromMorphoToComp(
        address _cErc20Address,
        uint256 _amount,
        address _lenderToAvoid
    ) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        uint256 remainingToMove = _amount; // In underlying
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(_cErc20Address);
        uint256 length = lendersOnMorpho[_cErc20Address].length();
        address lender = lendersOnMorpho[_cErc20Address].getHead();
        uint256 i;

        while (remainingToMove > 0 && i < length) {
            if (lender != _lenderToAvoid) {
                uint256 onMorpho = lendingBalanceInOf[_cErc20Address][lender].onMorpho; // In mUnit

                if (onMorpho > 0) {
                    uint256 toMove; // In underlying
                    if (onMorpho.mul(mExchangeRate) <= remainingToMove) {
                        toMove = onMorpho.mul(mExchangeRate);
                        lendingBalanceInOf[_cErc20Address][lender].onMorpho = 0;
                    } else {
                        toMove = remainingToMove;
                        lendingBalanceInOf[_cErc20Address][lender].onMorpho -= remainingToMove.div(
                            mExchangeRate
                        );
                    }
                    remainingToMove -= toMove; // In underlying
                    lendingBalanceInOf[_cErc20Address][lender].onComp += toMove.div(cExchangeRate); // In cToken
                    _updateLenderList(_cErc20Address, lender);
                    emit LenderMovedFromMorphoToComp(lender, _cErc20Address, toMove);
                }

                lender = lendersOnMorpho[_cErc20Address].getHead();
            } else {
                lender = lendersOnMorpho[_cErc20Address].getNext(lender);
            }

            i++;
        }
        require(remainingToMove == 0, "_moveLendersFromMorphoToComp: not enough liquidity to move");
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @dev Note: mUnitExchangeRate must have been upated before calling this function.
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
        uint256 length = borrowersOnMorpho[_cErc20Address].length();
        uint256 i;

        while (remainingToMove > 0 && i < length) {
            address borrower = borrowersOnMorpho[_cErc20Address].getHead();

            if (borrowingBalanceInOf[_cErc20Address][borrower].onMorpho > 0) {
                uint256 toMove; // In underlying
                if (
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho.mul(mExchangeRate) <=
                    remainingToMove
                ) {
                    toMove = borrowingBalanceInOf[_cErc20Address][borrower].onMorpho.mul(
                        mExchangeRate
                    );
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho = 0;
                } else {
                    toMove = remainingToMove;
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho -= remainingToMove.div(
                        mExchangeRate
                    );
                }
                remainingToMove -= toMove;
                borrowingBalanceInOf[_cErc20Address][borrower].onComp += toMove.div(borrowIndex);

                _updateBorrowerList(_cErc20Address, borrower);
                emit BorrowerMovedFromMorphoToComp(borrower, _cErc20Address, toMove);
            }

            i++;
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @dev Note: mUnitExchangeRate must have been upated before calling this function.
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
        uint256 length = borrowersOnComp[_cErc20Address].length();
        uint256 i;

        while (remainingToMove > 0 && i < length) {
            address borrower = borrowersOnComp[_cErc20Address].getHead();

            if (borrowingBalanceInOf[_cErc20Address][borrower].onComp > 0) {
                uint256 onCompInUnderlying = borrowingBalanceInOf[_cErc20Address][borrower]
                    .onComp
                    .mul(borrowIndex);
                uint256 toMove; // in underlying;
                if (onCompInUnderlying <= remainingToMove) {
                    toMove = onCompInUnderlying;
                    borrowingBalanceInOf[_cErc20Address][borrower].onComp = 0;
                } else {
                    toMove = remainingToMove;
                    borrowingBalanceInOf[_cErc20Address][borrower].onComp -= remainingToMove.div(
                        borrowIndex
                    );
                }
                remainingToMove -= toMove;
                borrowingBalanceInOf[_cErc20Address][borrower].onMorpho += toMove.div(
                    mExchangeRate
                );

                _updateBorrowerList(_cErc20Address, borrower);
                emit BorrowerMovedFromCompToMorpho(borrower, _cErc20Address, toMove);
            }

            i++;
        }
    }

    /**
     * @dev Moves lending balance of an account from Morpho to Compound.
     * @param _account The address of the account to move balance.
     */
    function _moveLenderFromMorphoToComp(address _account) internal {
        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cErc20Entered = enteredMarkets[_account][i];
            uint256 mExchangeRate = compMarketsManager.mUnitExchangeRate(cErc20Entered);
            uint256 cExchangeRate = ICErc20(cErc20Entered).exchangeRateCurrent();
            uint256 onMorphoInUnderlying = lendingBalanceInOf[cErc20Entered][_account].onMorpho.mul(
                mExchangeRate
            );

            if (onMorphoInUnderlying > 0) {
                lendingBalanceInOf[cErc20Entered][_account].onComp += onMorphoInUnderlying.div(
                    cExchangeRate
                ); // In cToken
                lendingBalanceInOf[cErc20Entered][_account].onMorpho -= onMorphoInUnderlying.div(
                    mExchangeRate
                ); // In mUnit

                _moveBorrowersFromMorphoToComp(cErc20Entered, onMorphoInUnderlying);
                _updateLenderList(cErc20Entered, _account);
                emit LenderMovedFromMorphoToComp(_account, cErc20Entered, onMorphoInUnderlying);
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

    /**
     * @param _account The user to determine liquidity for.
     * @param _cErc20Address The market to hypothetically redeem/borrow in.
     * @param _redeemAmount The number of tokens to hypothetically redeem.
     * @param _borrowedAmount The amount of underlying to hypothetically borrow.
     * @return (debtPrice, maxDebtPrice, collateralPrice).
     */
    function _getUserHypotheticalStateBalances(
        address _account,
        address _cErc20Address,
        uint256 _redeemAmount,
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
                borrowingBalanceInOf[vars.cErc20Entered][_account].onComp.mul(
                    ICErc20(vars.cErc20Entered).borrowIndex()
                ) +
                borrowingBalanceInOf[vars.cErc20Entered][_account].onMorpho.mul(vars.mExchangeRate);
            vars.toAddCollateral =
                lendingBalanceInOf[vars.cErc20Entered][_account].onComp.mul(
                    ICErc20(vars.cErc20Entered).exchangeRateCurrent()
                ) +
                lendingBalanceInOf[vars.cErc20Entered][_account].onMorpho.mul(vars.mExchangeRate);

            vars.underlyingPrice = compoundOracle.getUnderlyingPrice(vars.cErc20Entered);
            if (_cErc20Address == vars.cErc20Entered) {
                vars.toAddDebt += _borrowedAmount;
                stateBalance.redeemedValue = _redeemAmount.mul(vars.underlyingPrice);
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
     *  @param _account The address of the borrower to add or remove.
     */
    function _updateBorrowerList(address _cErc20Address, address _account) internal {
        if (
            borrowingBalanceInOf[_cErc20Address][_account].onComp <
            compMarketsManager.thresholds(_cErc20Address, ICompMarketsManager.Threshold.CdUnit)
        ) borrowersOnComp[_cErc20Address].remove(_account);
        else borrowersOnComp[_cErc20Address].addTail(_account);
        if (
            borrowingBalanceInOf[_cErc20Address][_account].onMorpho <
            compMarketsManager.thresholds(_cErc20Address, ICompMarketsManager.Threshold.MUnit)
        ) borrowersOnMorpho[_cErc20Address].remove(_account);
        else borrowersOnMorpho[_cErc20Address].addTail(_account);
    }

    /** @dev Updates lender lists.
     *  @param _cErc20Address The address of the market on which we want to update the lender lists.
     *  @param _account The address of the lender to add or remove.
     */
    function _updateLenderList(address _cErc20Address, address _account) internal {
        if (
            lendingBalanceInOf[_cErc20Address][_account].onComp <
            compMarketsManager.thresholds(_cErc20Address, ICompMarketsManager.Threshold.CToken)
        ) lendersOnComp[_cErc20Address].remove(_account);
        else lendersOnComp[_cErc20Address].addTail(_account);
        if (
            lendingBalanceInOf[_cErc20Address][_account].onMorpho <
            compMarketsManager.thresholds(_cErc20Address, ICompMarketsManager.Threshold.MUnit)
        ) lendersOnMorpho[_cErc20Address].remove(_account);
        else lendersOnMorpho[_cErc20Address].addTail(_account);
    }
}
