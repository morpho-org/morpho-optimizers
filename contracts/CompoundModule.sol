// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import "./libraries/DoubleLinkedList.sol";
import {ICErc20, ICEth, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with cERC20 tokens as lending/borrowing assets.
 */
contract CompoundModule is ReentrancyGuard, Ownable {
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

    struct StateBalance {
        uint256 debtValue; // The total debt value (in USD).
        uint256 maxDebtValue; // The maximum debt value available thanks to the collateral (in USD).
        uint256 collateralValue; // The collateral value (in USD).
    }

    struct Market {
        bool isListed; // Whether or not this market is listed.
        uint256 BPY; // Block Percentage Yield ("midrate").
        uint256 collateralFactorMantissa; // Multiplier representing the most one can borrow against their collateral in this market (0.9 => borrow 90% of collateral value max). Between 0 and 1.
        uint256 currentExchangeRate; // current exchange rate from mUnit to underlying.
        uint256 lastUpdateBlockNumber; // Last time currentExchangeRate was updated.
        uint256[3] thresholds; // Thresholds below the ones we remove lenders and borrowers from the lists. 0 -> Underlying, 1 -> cToken, 2 -> mUnit
        DoubleLinkedList.List lendersOnMorpho; // Lenders on Morpho.
        DoubleLinkedList.List lendersOnComp; // Lenders on Compound.
        DoubleLinkedList.List borrowersOnMorpho; // Borrowers on Morpho.
        DoubleLinkedList.List borrowersOnComp; // Borrowers on Compound.
    }

    /* Storage */

    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => mapping(address => LendingBalance))
        public lendingBalanceInOf; // Lending balance of user.
    mapping(address => mapping(address => BorrowingBalance))
        public borrowingBalanceInOf; // Borrowing balance of user.
    mapping(address => mapping(address => uint256))
        public collateralBalanceInOf; // Collateral balance of user.
    mapping(address => mapping(address => uint256)) public test;

    mapping(address => Market) private markets; // Markets of Morpho.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.

    uint256 public liquidationIncentive = 1.1e18; // Incentive for liquidators in percentage (110%).

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;

    /* Events */

    event Lend(address _account, address _cErc20Address, uint256 _amount);
    event Withdraw(address _account, address _cErc20Address, uint256 _amount);
    event Borrow(address _account, address _cErc20Address, uint256 _amount);
    event Repay(address _account, address _cErc20Address, uint256 _amount);
    event ProvideCollateral(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );
    event RedeemCollateral(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );
    event UpdateBPY(address _cErc20Address, uint256 _newValue);
    event UpdateCurrentExchangeRate(address _cErc20Address, uint256 _newValue);
    event UpdateThreshold(
        address _cErc20Address,
        uint256 _thresholdType,
        uint256 _newValue
    );
    event LenderMovedFromMorphoToComp(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );
    event LenderMovedFromCompToMorpho(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );
    event BorrowerMovedFromMorphoToComp(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );
    event BorrowerMovedFromCompToMorpho(
        address _account,
        address _cErc20Address,
        uint256 _amount
    );

    /* Constructor */

    constructor(address _proxyComptrollerAddress) {
        comptroller = IComptroller(_proxyComptrollerAddress);
        address compoundOracleAddress = comptroller.oracle();
        compoundOracle = ICompoundOracle(compoundOracleAddress);
    }

    /* External */

    /** @dev Sets a market as listed.
     *  @param _cTokenAddress The address of the market to list.
     */
    function listMarket(address _cTokenAddress) external onlyOwner {
        markets[_cTokenAddress].isListed = true;
    }

    /** @dev Sets a market as unlisted.
     *  @param _cTokenAddress The address of the market to unlist.
     */
    function unlistMarket(address _cTokenAddress) external onlyOwner {
        markets[_cTokenAddress].isListed = false;
    }

    /** @dev Updates thresholds below the ones lenders and borrowers are removed from lists.
     *  @param _thresholdType Which threshold must be updated. 0 -> Underlying, 1 -> cToken, 2 -> mUnit
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(
        address _cErc20Address,
        uint256 _thresholdType,
        uint256 _newThreshold
    ) external onlyOwner {
        require(_newThreshold > 0, "New THRESHOLD must be strictly positive.");
        markets[_cErc20Address].thresholds[_thresholdType] = _newThreshold;
    }

    function getMarketInfo(address _cTokenAddress)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            markets[_cTokenAddress].BPY,
            markets[_cTokenAddress].collateralFactorMantissa,
            markets[_cTokenAddress].currentExchangeRate
        );
    }

    /** @dev Lends ERC20 tokens in a specific market.
     *  @param _cErc20Address The address of the market the user wants to lend.
     *  @param _amount The amount to lend in ERC20 tokens.
     */
    function lend(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        require(
            _amount >= markets[_cErc20Address].thresholds[0],
            "Amount cannot be less than THRESHOLD."
        );
        require(_lendAuthorization(_cErc20Address));
        Market storage market = markets[_cErc20Address];

        if (!checkMembership(msg.sender, _cErc20Address)) {
            accountMembership[_cErc20Address][msg.sender] = true;
            enteredMarkets[msg.sender].push(_cErc20Address);
        }

        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();

        // If some borrowers are on Compound, we must move them to Morpho
        if (market.borrowersOnComp.length() > 0) {
            uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);
            // Find borrowers and move them to Morpho
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                _cErc20Address,
                _amount
            ); // In underlying

            // Repay Compound
            // TODO: verify that not too much is sent to Compound
            uint256 toRepay = _amount - remainingToSupplyToComp;
            // Update lender balance
            lendingBalanceInOf[_cErc20Address][msg.sender].onMorpho += toRepay
                .div(mExchangeRate); // In mUnit
            market.lendersOnMorpho.addTail(msg.sender);
            cErc20Token.repayBorrow(toRepay);

            if (remainingToSupplyToComp > 0) {
                lendingBalanceInOf[_cErc20Address][msg.sender]
                    .onComp += remainingToSupplyToComp.div(cExchangeRate); // In cToken
                _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp); // Revert on error
            }
        } else {
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp += _amount
                .div(cExchangeRate); // In cToken
            _supplyErc20ToComp(_cErc20Address, _amount); // Revert on error
        }

        if (
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp >=
            market.thresholds[1]
        ) market.lendersOnComp.addTail(msg.sender);
        emit Lend(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cErc20Address The address of the markets the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        if (!checkMembership(msg.sender, _cErc20Address)) {
            accountMembership[_cErc20Address][msg.sender] = true;
            enteredMarkets[msg.sender].push(_cErc20Address);
        }

        require(
            _borrowAuthorization(_cErc20Address, msg.sender, _amount),
            "Not enough collateral."
        );
        Market storage market = markets[_cErc20Address];

        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);

        // If some borrowers are on Compound, we must move them to Morpho
        if (market.lendersOnComp.length() > 0) {
            uint256 remainingToBorrowOnComp = _moveLendersFromCompToMorpho(
                _cErc20Address,
                _amount,
                msg.sender
            ); // In underlying
            uint256 toRedeem = _amount - remainingToBorrowOnComp;

            if (toRedeem > 0) {
                borrowingBalanceInOf[_cErc20Address][msg.sender]
                    .onMorpho += toRedeem.div(mExchangeRate); // In mUnit
                market.borrowersOnMorpho.addTail(msg.sender);
                _redeemErc20FromComp(_cErc20Address, toRedeem); // Revert on error
            }

            // If not enough cTokens on Morpho, we must borrow it on Compound
            if (remainingToBorrowOnComp > 0) {
                require(
                    cErc20Token.borrow(remainingToBorrowOnComp) == 0,
                    "Borrow on Compound failed."
                );
                borrowingBalanceInOf[_cErc20Address][msg.sender]
                    .onComp += remainingToBorrowOnComp.div(
                    cErc20Token.borrowIndex()
                ); // In cdUnit
                market.borrowersOnComp.addTail(msg.sender);
            }
        } else {
            require(
                cErc20Token.borrow(_amount) == 0,
                "Borrow on Compound failed."
            );
            borrowingBalanceInOf[_cErc20Address][msg.sender].onComp += _amount
                .div(cErc20Token.borrowIndex()); // In cdUnit
        }

        // Transfer ERC20 tokens to borrower
        erc20Token.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Repays debt of the user.
     *  @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        _repay(_cErc20Address, msg.sender, _amount);
    }

    /** @dev Withdraws ERC20 tokens from lending.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in tokens to withdraw from lending.
     */
    function withdraw(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        require(_withdrawAuthorization(_cErc20Address, _amount));
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        Market storage market = markets[_cErc20Address];

        uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = lendingBalanceInOf[_cErc20Address][
            msg.sender
        ].onComp.mul(cExchangeRate);

        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where we can directly withdraw unused liquidity from Compound
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp -= _amount
                .div(cExchangeRate); // In cToken
            _redeemErc20FromComp(_cErc20Address, _amount); // Revert on error
        } else {
            // First, we take all the unused liquidy on Compound.
            _redeemErc20FromComp(_cErc20Address, amountOnCompInUnderlying); // Revert on error
            lendingBalanceInOf[_cErc20Address][msg.sender]
                .onComp -= amountOnCompInUnderlying.div(cExchangeRate);
            // Then, search for the remaining liquidity on Morpho
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying
            lendingBalanceInOf[_cErc20Address][msg.sender]
                .onMorpho -= remainingToWithdraw.div(mExchangeRate); // In mUnit
            uint256 cTokenContractBalanceInUnderlying = cErc20Token
                .balanceOf(address(this))
                .mul(cExchangeRate);

            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough cTokens in the contract to use
                require(
                    _moveLendersFromCompToMorpho(
                        _cErc20Address,
                        remainingToWithdraw,
                        msg.sender
                    ) == 0,
                    "Remaining to move should be 0."
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
                    _moveBorrowersFromMorphoToComp(
                        _cErc20Address,
                        remainingToWithdraw
                    ) == 0,
                    "All liquidity should have been moved."
                );
                require(
                    cErc20Token.borrow(remainingToWithdraw) == 0,
                    "Borrow on Compound failed."
                );
            }
        }

        // Transfer back the ERC20 tokens
        erc20Token.safeTransfer(msg.sender, _amount);

        // Remove lenders from lists if needed
        if (
            lendingBalanceInOf[_cErc20Address][msg.sender].onComp <
            market.thresholds[1]
        ) market.lendersOnComp.remove(msg.sender);
        if (
            lendingBalanceInOf[_cErc20Address][msg.sender].onMorpho <
            market.thresholds[2]
        ) market.lendersOnMorpho.remove(msg.sender);
        emit Withdraw(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Allows a borrower to provide collateral.
     *  @param _cErc20Address The address of the market the user wants to provide collateral to.
     *  @param _amount The amount in ERC20 tokens to provide.
     */
    function provideCollateral(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        require(_amount > 0, "Amount cannot be 0.");

        if (!checkMembership(msg.sender, _cErc20Address)) {
            accountMembership[_cErc20Address][msg.sender] = true;
            enteredMarkets[msg.sender].push(_cErc20Address);
        }

        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        // Update the collateral balance of the sender in cToken
        collateralBalanceInOf[_cErc20Address][msg.sender] += _amount.div(
            cErc20Token.exchangeRateCurrent()
        );
        _supplyErc20ToComp(_cErc20Address, _amount); // Revert on error
        emit ProvideCollateral(msg.sender, _cErc20Address, _amount);
    }

    /** @dev Allows a borrower to redeem her collateral in underlying.
     *  @param _cErc20Address The address of the market the user wants to redeem collateral from.
     *  @param _amount The amount in ERC20 tokens to redeem.
     */
    function redeemCollateral(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        require(_redeemAuthorization(_cErc20Address, msg.sender, _amount), "");
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountInCToken = _amount.div(cExchangeRate);
        collateralBalanceInOf[_cErc20Address][msg.sender] -= amountInCToken; // In cToken

        _redeemErc20FromComp(_cErc20Address, _amount); // Revert on error

        // Transfer ERC20 tokens to the borrower
        erc20Token.safeTransfer(msg.sender, _amount);
        emit RedeemCollateral(msg.sender, _cErc20Address, _amount);
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
        require(
            _liquidateAuthorization(_cErc20CollateralAddress, _borrower),
            "Liquidation not allowed"
        );

        _repay(_cErc20BorrowedAddress, _borrower, _amount);

        // Calculate the amount of token to seize from collateral
        uint256 priceCollateralMantissa = compoundOracle.getUnderlyingPrice(
            _cErc20CollateralAddress
        );
        uint256 priceBorrowedMantissa = compoundOracle.getUnderlyingPrice(
            _cErc20BorrowedAddress
        );
        require(
            priceCollateralMantissa != 0 && priceBorrowedMantissa != 0,
            "Oracle failed."
        );

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */

        uint256 cTokenAmountToSeize = _amount
            .mul(priceBorrowedMantissa)
            .div(priceCollateralMantissa)
            .mul(liquidationIncentive)
            .div(ICErc20(_cErc20CollateralAddress).exchangeRateCurrent());

        require(
            cTokenAmountToSeize <=
                collateralBalanceInOf[_cErc20CollateralAddress][_borrower],
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceInOf[_cErc20CollateralAddress][
            _borrower
        ] -= cTokenAmountToSeize;
        _redeemErc20FromComp(_cErc20CollateralAddress, _amount); // Revert on error

        ICErc20 cErc20CollateralToken = ICErc20(_cErc20CollateralAddress);
        IERC20 erc20CollateralToken = IERC20(
            cErc20CollateralToken.underlying()
        );

        // Transfer ERC20 tokens to liquidator
        erc20CollateralToken.safeTransfer(msg.sender, _amount);
    }

    /* Public */

    /** @dev Creates new market to borrow/lend.
     *  @param _cTokensAddresses The addresses of the markets to add.
     */
    function createMarkets(address[] memory _cTokensAddresses)
        public
        onlyOwner
    {
        comptroller.enterMarkets(_cTokensAddresses);
        for (uint256 k = 0; k < _cTokensAddresses.length; k++) {
            address cTokenAddress = _cTokensAddresses[k];
            Market storage market = markets[cTokenAddress];
            market.currentExchangeRate = 1e18;
            market.collateralFactorMantissa = 75e16;
            market.lastUpdateBlockNumber = block.number;
            market.thresholds = [1e18, 1e7, 1e18];
            updateBPY(cTokenAddress);
            updateCollateralFactor(cTokenAddress);
        }
    }

    /**
     * @dev Returns whether the given account is entered in the given asset
     * @param _account The address of the account to check
     * @param _cTokenAddress The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address _account, address _cTokenAddress)
        public
        view
        returns (bool)
    {
        return accountMembership[_cTokenAddress][_account];
    }

    /** @dev Updates the collateral factor related to cToken.
     *  @param _cErc20Address The address of the market we want to update.
     */
    function updateCollateralFactor(address _cErc20Address) public {
        (, uint256 collateralFactor, ) = comptroller.markets(_cErc20Address);
        markets[_cErc20Address].collateralFactorMantissa = collateralFactor;
    }

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`currentExchangeRate`).
     *  @param _cErc20Address The address of the market we want to update.
     */
    function updateBPY(address _cErc20Address) public {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);

        // Update BPY
        uint256 lendBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        markets[_cErc20Address].BPY = Math.average(lendBPY, borrowBPY);

        emit UpdateBPY(_cErc20Address, markets[_cErc20Address].BPY);

        // Update currentExchangeRate
        updateCurrentExchangeRate(_cErc20Address);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (BPY) since the last time it has been updated.
     *  @param _cErc20Address The address of the market we want to update.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateCurrentExchangeRate(address _cErc20Address)
        public
        returns (uint256)
    {
        Market storage market = markets[_cErc20Address];
        uint256 currentBlock = block.number;

        if (market.lastUpdateBlockNumber == currentBlock) {
            return market.currentExchangeRate;
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                market.lastUpdateBlockNumber;

            uint256 newCurrentExchangeRate = market.currentExchangeRate.mul(
                (1e18 + market.BPY).pow(
                    PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                )
            );

            emit UpdateCurrentExchangeRate(
                _cErc20Address,
                newCurrentExchangeRate
            );

            // Update currentExchangeRate
            market.currentExchangeRate = newCurrentExchangeRate;

            // Update lastUpdateBlockNumber
            market.lastUpdateBlockNumber = currentBlock;

            return newCurrentExchangeRate;
        }
    }

    /**
     * @param _account The user to determine liquidity for.
     * @param _cErc20Address The market to hypothetically redeem/borrow in.
     * @param _redeemAmount The number of tokens to hypothetically redeem.
     * @param _borrowedAmount The amount of underlying to hypothetically borrow.
     * @return (debtPrice, maxDebtPrice, collateralPrice).
     */
    function getUserHypotheticalStateBalances(
        address _account,
        address _cErc20Address,
        uint256 _redeemAmount,
        uint256 _borrowedAmount
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        StateBalance memory stateBalance;

        for (uint256 i; i < enteredMarkets[_account].length; i++) {
            address cErc20Entered = enteredMarkets[_account][i];

            uint256 toAddDebt = borrowingBalanceInOf[cErc20Entered][_account]
                .onComp
                .mul(ICErc20(cErc20Entered).borrowIndex()) +
                borrowingBalanceInOf[cErc20Entered][_account].onMorpho.mul(
                    updateCurrentExchangeRate(cErc20Entered)
                );
            uint256 toAddCollateral = collateralBalanceInOf[cErc20Entered][
                _account
            ].mul(ICErc20(cErc20Entered).exchangeRateCurrent());

            if (_cErc20Address == cErc20Entered) {
                toAddDebt += _borrowedAmount;
                toAddCollateral += _redeemAmount;
            }

            toAddCollateral = toAddCollateral.mul(
                compoundOracle.getUnderlyingPrice(cErc20Entered)
            );

            stateBalance.debtValue += toAddDebt.mul(
                compoundOracle.getUnderlyingPrice(cErc20Entered)
            );
            stateBalance.collateralValue += toAddCollateral;
            stateBalance.maxDebtValue += toAddCollateral.mul(
                markets[cErc20Entered].collateralFactorMantissa
            );
        }

        return (
            stateBalance.debtValue,
            stateBalance.maxDebtValue,
            stateBalance.collateralValue
        );
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
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);
        Market storage market = markets[_cErc20Address];

        if (borrowingBalanceInOf[_cErc20Address][_borrower].onComp > 0) {
            uint256 onCompInUnderlying = borrowingBalanceInOf[_cErc20Address][
                _borrower
            ].onComp.mul(cErc20Token.borrowIndex());

            if (_amount <= onCompInUnderlying) {
                borrowingBalanceInOf[_cErc20Address][_borrower]
                    .onComp -= _amount.div(cErc20Token.borrowIndex()); // In cdUnit
                // Repay Compound
                erc20Token.safeApprove(_cErc20Address, _amount);
                cErc20Token.repayBorrow(_amount);
            } else {
                // Move the remaining liquidity to Compound
                uint256 remainingToSupplyToComp = _amount - onCompInUnderlying; // In underlying
                borrowingBalanceInOf[_cErc20Address][_borrower]
                    .onMorpho -= remainingToSupplyToComp.div(mExchangeRate);
                borrowingBalanceInOf[_cErc20Address][_borrower]
                    .onComp -= onCompInUnderlying.div(
                    cErc20Token.borrowIndex()
                ); // We use a fresh new borrowIndex since the borrowIndex is updated after a repay

                _moveLendersFromMorphoToComp(
                    _cErc20Address,
                    remainingToSupplyToComp,
                    _borrower
                ); // Revert on error

                // Repay Compound
                erc20Token.safeApprove(_cErc20Address, onCompInUnderlying);
                cErc20Token.repayBorrow(onCompInUnderlying); // Revert on error

                if (remainingToSupplyToComp > 0)
                    _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp);
            }
        } else {
            borrowingBalanceInOf[_cErc20Address][_borrower].onMorpho -= _amount
                .div(mExchangeRate); // In mUnit
            _moveLendersFromMorphoToComp(_cErc20Address, _amount, _borrower);
            _supplyErc20ToComp(_cErc20Address, _amount);
        }

        // Remove borrower from lists if needed
        if (
            borrowingBalanceInOf[_cErc20Address][_borrower].onComp <
            market.thresholds[1]
        ) market.borrowersOnComp.remove(_borrower);
        if (
            borrowingBalanceInOf[_cErc20Address][_borrower].onMorpho <
            market.thresholds[2]
        ) market.borrowersOnMorpho.remove(_borrower);
        emit Repay(_borrower, _cErc20Address, _amount);
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount in ERC20 tokens to supply.
     */
    function _supplyErc20ToComp(address _cErc20Address, uint256 _amount)
        internal
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        // Approve transfer on the ERC20 contract
        erc20Token.safeApprove(_cErc20Address, _amount);
        // Mint cTokens
        require(cErc20Token.mint(_amount) == 0, "cToken minting failed.");
    }

    /** @dev Redeems ERC20 tokens from Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount The amount of tokens to be redeemed.
     */
    function _redeemErc20FromComp(address _cErc20Address, uint256 _amount)
        internal
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        require(
            cErc20Token.redeemUnderlying(_amount) == 0,
            "Redeem ERC20 on Compound failed."
        );
    }

    /** @dev Finds liquidity on Compound and moves it to Morpho.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
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
        Market storage market = markets[_cErc20Address];
        uint256 mExchangeRate = market.currentExchangeRate;
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        address lender = market.lendersOnComp.getHead();
        uint256 i;

        while (remainingToMove > 0 && i < market.lendersOnComp.length()) {
            if (lender != _lenderToAvoid) {
                uint256 onComp = lendingBalanceInOf[_cErc20Address][lender]
                    .onComp; // In cToken

                if (onComp > 0) {
                    uint256 amountToMove = Math.min(
                        onComp.mul(cExchangeRate),
                        remainingToMove
                    ); // In underlying
                    remainingToMove -= amountToMove;
                    lendingBalanceInOf[_cErc20Address][lender]
                        .onComp -= amountToMove.div(cExchangeRate); // In cToken
                    lendingBalanceInOf[_cErc20Address][lender]
                        .onMorpho += amountToMove.div(mExchangeRate); // In mUnit

                    // Update lists if needed
                    if (
                        lendingBalanceInOf[_cErc20Address][lender].onComp <
                        market.thresholds[1]
                    ) market.lendersOnComp.remove(lender);
                    if (
                        lendingBalanceInOf[_cErc20Address][lender].onMorpho >=
                        market.thresholds[2]
                    ) market.lendersOnMorpho.addTail(lender);

                    emit LenderMovedFromCompToMorpho(
                        lender,
                        _cErc20Address,
                        amountToMove
                    );
                }
            }

            lender = market.lendersOnComp.getNext(lender);
            i++;
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
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
        Market storage market = markets[_cErc20Address];
        uint256 mExchangeRate = market.currentExchangeRate;
        address lender = market.lendersOnMorpho.getHead();
        uint256 i;

        while (remainingToMove > 0 && i < market.lendersOnMorpho.length()) {
            if (lender != _lenderToAvoid) {
                uint256 onMorpho = lendingBalanceInOf[_cErc20Address][lender]
                    .onMorpho; // In mUnit

                if (onMorpho > 0) {
                    uint256 amountToMove = Math.min(
                        onMorpho.mul(mExchangeRate),
                        remainingToMove
                    ); // In underlying
                    remainingToMove -= amountToMove; // In underlying
                    lendingBalanceInOf[_cErc20Address][lender]
                        .onComp += amountToMove.div(cExchangeRate); // In cToken
                    lendingBalanceInOf[_cErc20Address][lender]
                        .onMorpho -= amountToMove.div(mExchangeRate); // In mUnit

                    // Update lists if needed
                    if (
                        lendingBalanceInOf[_cErc20Address][lender].onComp >=
                        market.thresholds[1]
                    ) market.lendersOnComp.addTail(lender);
                    if (
                        lendingBalanceInOf[_cErc20Address][lender].onMorpho <
                        market.thresholds[2]
                    ) market.lendersOnMorpho.remove(lender);

                    emit LenderMovedFromMorphoToComp(
                        lender,
                        _cErc20Address,
                        amountToMove
                    );
                }
            }

            lender = market.lendersOnMorpho.getNext(lender);
            i++;
        }
        require(remainingToMove == 0, "Not enough liquidity to unuse.");
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _moveBorrowersFromMorphoToComp(
        address _cErc20Address,
        uint256 _amount
    ) internal returns (uint256 remainingToMatch) {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMatch = _amount;
        Market storage market = markets[_cErc20Address];
        uint256 mExchangeRate = market.currentExchangeRate;
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 i;

        while (remainingToMatch > 0 && i < market.borrowersOnMorpho.length()) {
            address borrower = market.borrowersOnMorpho.getHead();

            if (borrowingBalanceInOf[_cErc20Address][borrower].onMorpho > 0) {
                uint256 toMatch = Math.min(
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho.mul(
                        mExchangeRate
                    ),
                    remainingToMatch
                ); // In underlying

                remainingToMatch -= toMatch;
                borrowingBalanceInOf[_cErc20Address][borrower].onComp += toMatch
                    .div(borrowIndex);
                borrowingBalanceInOf[_cErc20Address][borrower]
                    .onMorpho -= toMatch.div(mExchangeRate);

                // Update lists if needed
                if (
                    borrowingBalanceInOf[_cErc20Address][borrower].onComp >=
                    market.thresholds[1]
                ) market.borrowersOnComp.addTail(borrower);
                if (
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho <
                    market.thresholds[2]
                ) market.borrowersOnMorpho.remove(borrower);

                emit BorrowerMovedFromMorphoToComp(
                    borrower,
                    _cErc20Address,
                    toMatch
                );
            }
            i++;
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
     *  @param _cErc20Address The address of the market on which we want to move users.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _moveBorrowersFromCompToMorpho(
        address _cErc20Address,
        uint256 _amount
    ) internal returns (uint256 remainingToMatch) {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        remainingToMatch = _amount;
        Market storage market = markets[_cErc20Address];
        uint256 mExchangeRate = market.currentExchangeRate;
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 i;

        while (remainingToMatch > 0 && i < market.borrowersOnComp.length()) {
            address borrower = market.borrowersOnComp.getHead();

            if (borrowingBalanceInOf[_cErc20Address][borrower].onComp > 0) {
                uint256 onCompInUnderlying = borrowingBalanceInOf[
                    _cErc20Address
                ][borrower].onComp.mul(borrowIndex);
                uint256 toMatch = Math.min(
                    onCompInUnderlying,
                    remainingToMatch
                ); // In underlying

                remainingToMatch -= toMatch;
                borrowingBalanceInOf[_cErc20Address][borrower].onComp -= toMatch
                    .div(borrowIndex);
                borrowingBalanceInOf[_cErc20Address][borrower]
                    .onMorpho += toMatch.div(mExchangeRate);

                // Update lists if needed
                if (
                    borrowingBalanceInOf[_cErc20Address][borrower].onComp <
                    market.thresholds[1]
                ) market.borrowersOnComp.remove(borrower);
                if (
                    borrowingBalanceInOf[_cErc20Address][borrower].onMorpho >=
                    market.thresholds[2]
                ) market.borrowersOnMorpho.addTail(borrower);

                emit BorrowerMovedFromCompToMorpho(
                    borrower,
                    _cErc20Address,
                    toMatch
                );
            }
            i++;
        }
    }

    /** @dev Returns whether the user can lend on a specific market or not.
     *  @param _cErc20Address The address of the market.
     *  @return Whether the user is allowed or not.
     */
    function _lendAuthorization(address _cErc20Address)
        internal
        view
        returns (bool)
    {
        require(markets[_cErc20Address].isListed, "Market not listed");
        return true;
    }

    /** @dev Returns whether the user can withdraw from a specific market or not.
     *  @param _cErc20Address The address of the market.
     *  @param _amount The amount to be withdrawn in underlying.
     *  @return Whether the user is allowed or not.
     */
    function _withdrawAuthorization(address _cErc20Address, uint256 _amount)
        internal
        view
        returns (bool)
    {
        require(markets[_cErc20Address].isListed, "Market not listed");
        require(_amount > 0, "Amount cannot be 0.");
        return true;
    }

    /** @dev Returns whether the user can borrow on a specific market or not.
     *  @param _cErc20Address The address of the market.
     *  @param _account The address of the user.
     *  @param _amount The amount to be borrowed in underlying.
     *  @return Whether the user is allowed or not.
     */
    function _borrowAuthorization(
        address _cErc20Address,
        address _account,
        uint256 _amount
    ) internal returns (bool) {
        require(markets[_cErc20Address].isListed, "Market not listed");
        require(
            _amount >= markets[_cErc20Address].thresholds[0],
            "Amount cannot be less than THRESHOLD."
        );
        (
            uint256 debtValue,
            uint256 maxDebtValue,

        ) = getUserHypotheticalStateBalances(
            _account,
            _cErc20Address,
            0,
            _amount
        );
        return debtValue < maxDebtValue;
    }

    /** @dev Returns whether the user can redeem from a specific market or not.
     *  @param _cErc20Address The address of the market.
     *  @param _account The address of the user.
     *  @param _amount The amount to be redeemed in underlying.
     *  @return Whether the user is allowed or not.
     */
    function _redeemAuthorization(
        address _cErc20Address,
        address _account,
        uint256 _amount
    ) internal returns (bool) {
        require(markets[_cErc20Address].isListed, "Market not listed");

        (
            uint256 debtValue,
            uint256 maxDebtValue,

        ) = getUserHypotheticalStateBalances(
            _account,
            _cErc20Address,
            _amount,
            0
        );
        return debtValue < maxDebtValue;
    }

    /** @dev Returns whether the user can repay her debt on a specific market or not.
     *  @param _cErc20Address The address of the market.
     *  @param _account The address of the user.
     *  @return Whether the user is allowed or not.
     */
    function _repayAuthorization(address _cErc20Address, address _account)
        internal
        view
        returns (bool)
    {
        require(markets[_cErc20Address].isListed, "Market not listed");
        // Check if the user entered this market
        require(
            checkMembership(_account, _cErc20Address),
            "Account not in market"
        );
        return true;
    }

    /** @dev Returns whether the user can liquidated or not.
     *  @param _cErc20Address The address of the market.
     *  @param _account The address of the user.
     *  @return Whether liquidation is allowed or not.
     */
    function _liquidateAuthorization(address _cErc20Address, address _account)
        internal
        returns (bool)
    {
        require(markets[_cErc20Address].isListed, "Market not listed");
        (
            uint256 debtValue,
            uint256 maxDebtValue,

        ) = getUserHypotheticalStateBalances(_account, address(0), 0, 0);
        return maxDebtValue > debtValue;
    }
}
