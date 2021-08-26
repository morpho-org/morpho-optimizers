pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import "./libraries/DoubleLinkedList.sol";
import {ICErc20, ICEth, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with ETH as collateral and a cERC20 token as lending/borrowing asset.
 */
contract CompoundModule is ReentrancyGuard, Ownable {
    using DoubleLinkedList for DoubleLinkedList.List;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* Structs */

    struct LendingBalance {
        uint256 onMorpho; // In mUnit (a unit that grows in value, to follow debt increase).
        uint256 onComp; // In cToken.
    }

    struct BorrowingBalance {
        uint256 onMorpho; // In mUnit.
        uint256 onComp; // In cdUnit. (a unit that grows in value, to follow debt increase). Multiply by current borrowIndex to get the underlying amount.
    }

    struct Market {
        bool isListed; // Whether or not this market is listed.
        uint256 collateralFactorMantissa; // Multiplier representing the most one can borrow against their collateral in this market (0.9 => borrow 90% of collateral value max). Between 0 and 1.
        uint256[] thresholds; // Thresholds below the ones we remove lenders and borrowers from the lists. 0 -> Underlying, 1 -> cToken, 2 -> mUnit
        DoubleLinkedList.List lendersOnMorpho; // Lenders on Morpho.
        DoubleLinkedList.List lendersOnComp; // Lenders on Compound.
        DoubleLinkedList.List borrowersOnMorpho; // Borrowers on Morpho.
        DoubleLinkedList.List borrowersOnComp; // Borrowers on Compound.
        mapping(address => LendingBalance) lendingBalanceOf; // Lending balance of user (ERC20/cERC20).
        mapping(address => BorrowingBalance) borrowingBalanceOf; // Borrowing balance of user (ERC20).
        mapping(address => uint256) collateralBalanceOf; // Collateral balance of user (cETH).
    }

    /* Storage */

    mapping(address => Market) private market; // Markets of Morpho.

    mapping(address => address[]) public enteredMarketsAsLenderOf; // Markets entered by a user as lender.
    mapping(address => address[]) public enteredMarketsForCollateral; // Markets entered by a user for collateral.
    mapping(address => address[]) public enteredMarketsAsBorrowerOf; // Markets entered by a user as borrower.

    uint256 public BPY; // Block Percentage Yield ("midrate").
    uint256 public collateralFactor = 75e16; // Collateral Factor related to cToken.
    uint256 public liquidationIncentive = 1.1e18; // Incentive for liquidators in percentage (110%).
    uint256 public currentExchangeRate = 1e18; // current exchange rate from mUnit to underlying.
    uint256 public lastUpdateBlockNumber; // Last time currentExchangeRate was updated.

    address public cErc20Address;
    address public cEthAddress;

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;

    /* Contructor */

    constructor(address _cEthAddress, address _proxyComptrollerAddress) {
        cEthAddress = _cEthAddress;
        comptroller = IComptroller(_proxyComptrollerAddress);
        address compoundOracleAddress = comptroller.oracle();
        compoundOracle = ICompoundOracle(compoundOracleAddress);
        lastUpdateBlockNumber = block.number;
    }

    /* External */

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

    /** @dev Lends ERC20 tokens.
     *  @param _cErc20Address The address of the market the user wants to enter.
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
        require(lendAuthorization(_cErc20Address, msg.sender, _amount));
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        erc20Token.transferFrom(msg.sender, address(this), _amount);
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();

        // If some borrowers are on Compound, we must move them to Morpho.
        if (market[_cErc20Address].borrowersOnComp.length() > 0) {
            uint256 mExchangeRate = updateCurrentExchangeRate();
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                _cErc20Address,
                _amount
            ); // In underlying.
            // Repay Compound.
            // TODO: verify that not too much is sent to Compound.
            uint256 toRepay = _amount - remainingToSupplyToComp;
            cErc20Token.repayBorrow(toRepay); // Revert on error.
            // Update lender balance.
            market[_cErc20Address]
                .lendingBalanceOf[msg.sender]
                .onMorpho += toRepay.div(mExchangeRate); // In mUnit.
            market[_cErc20Address].lendersOnMorpho.addTail(msg.sender);
            if (remainingToSupplyToComp > 0) {
                market[_cErc20Address]
                    .lendingBalanceOf[msg.sender]
                    .onComp += remainingToSupplyToComp.div(cExchangeRate); // In cToken.
                market[_cErc20Address].lendersOnComp.addTail(msg.sender);
                _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp); // Revert on error.
            }
        } else {
            market[_cErc20Address]
                .lendingBalanceOf[msg.sender]
                .onComp += _amount.div(cExchangeRate); // In cToken.
            market[_cErc20Address].lendersOnComp.addTail(msg.sender);
            _supplyErc20ToComp(_cErc20Address, _amount); // Revert on error.
        }
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _cErc20Address The address of the market the user wants to enter.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        require(
            _amount >= markets[_cErc20Address].thresholds[0],
            "Amount cannot be less than THRESHOLD."
        );
        require(borrowAuthorization(_cErc20Address, msg.sender, _amount));
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        ICEth cEthToken = ICEth(cEthAddress);
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 mExchangeRate = updateCurrentExchangeRate();
        uint256 amountBorrowedAfter = _amount +
            market[_cErc20Address].borrowingBalanceOf[msg.sender].onComp.mul(
                borrowIndex
            ) +
            market[_cErc20Address].borrowingBalanceOf[msg.sender].onMorpho.mul(
                mExchangeRate
            );
        // Calculate the collateral required.
        uint256 collateralRequiredInEth = getCollateralRequired(
            amountBorrowedAfter,
            collateralFactor,
            _cErc20Address,
            cEthAddress
        );
        uint256 collateralRequiredInCEth = collateralRequiredInEth.div(
            cEthToken.exchangeRateCurrent()
        );
        // Prevent to borrow dust without collateral.
        require(collateralRequiredInCEth > 0, "Borrowing is too low.");
        // Check if borrower has enough collateral.
        require(
            collateralRequiredInCEth <=
                market[_cErc20Address].collateralBalanceOf[msg.sender],
            "Not enough collateral."
        );

        uint256 remainingToBorrowOnComp = _moveLendersFromCompToMorpho(
            _cErc20Address,
            _amount,
            msg.sender
        ); // In underlying.
        uint256 toRedeem = _amount - remainingToBorrowOnComp;

        if (toRedeem > 0) {
            market[_cErc20Address]
                .borrowingBalanceOf[msg.sender]
                .onMorpho += toRedeem.div(mExchangeRate); // In mUnit.
            market[_cErc20Address].borrowersOnMorpho.addTail(msg.sender);
            _redeemErc20FromComp(_cErc20Address, toRedeem, false); // Revert on error.
        }

        // If not enough cTokens on Morpho, we must borrow it on Compound.
        if (remainingToBorrowOnComp > 0) {
            require(
                cErc20Token.borrow(remainingToBorrowOnComp) == 0,
                "Borrow on Compound failed."
            );
            market[_cErc20Address]
                .borrowingBalanceOf[msg.sender]
                .onComp += remainingToBorrowOnComp.div(
                cErc20Token.borrowIndex()
            ); // In cdUnit.
            market[_cErc20Address].borrowersOnComp.addTail(msg.sender);
        }
        // Transfer ERC20 tokens to borrower.
        erc20Token.safeTransfer(msg.sender, _amount);
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
        require(_amount > 0, "Amount cannot be 0.");
        require(withdrawAuthorization(_cErc20Address, msg.sender, _amount));
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        uint256 mExchangeRate = updateCurrentExchangeRate();
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = market[_cErc20Address]
            .lendingBalanceOf[msg.sender]
            .onComp
            .mul(cExchangeRate);

        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where we can directly withdraw unused liquidity on Compound.
            market[_cErc20Address]
                .lendingBalanceOf[msg.sender]
                .onComp -= _amount.div(cExchangeRate); // In cToken.
            _redeemErc20FromComp(_cErc20Address, _amount, false); // Revert on error.
        } else {
            // First, we take all the unused liquidy on Compound.
            _redeemErc20FromComp(
                _cErc20Address,
                amountOnCompInUnderlying,
                false
            ); // Revert on error.
            market[_cErc20Address]
                .lendingBalanceOf[msg.sender]
                .onComp -= amountOnCompInUnderlying.div(cExchangeRate);
            // Then, search for the remaining liquidity on Morpho.
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying.
            market[_cErc20Address]
                .lendingBalanceOf[msg.sender]
                .onMorpho -= remainingToWithdraw.div(mExchangeRate); // In mUnit.
            uint256 cTokenContractBalanceInUnderlying = cErc20Token
                .balanceOf(address(this))
                .mul(cExchangeRate);

            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough cTokens in the contract to use.
                require(
                    _moveLendersFromCompToMorpho(
                        _cErc20Address,
                        remainingToWithdraw,
                        msg.sender
                    ) == 0,
                    "Remaining to move should be 0."
                );
                _redeemErc20FromComp(
                    _cErc20Address,
                    remainingToWithdraw,
                    false
                ); // Revert on error.
            } else {
                // The contract does not have enough cTokens for the withdraw.
                // First, we use all the available cTokens in the contract.
                uint256 toRedeem = cTokenContractBalanceInUnderlying -
                    _moveLendersFromCompToMorpho(
                        _cErc20Address,
                        cTokenContractBalanceInUnderlying,
                        msg.sender
                    ); // The amount that can be redeemed for underlying.
                _redeemErc20FromComp(_cErc20Address, toRedeem, false); // Revert on error.
                // Update the remaining amount to withdraw to `msg.sender`.
                remainingToWithdraw -= toRedeem;
                // Then, we move borrowers not matched anymore from Morpho to Compound and borrow the amount directly on Compound.
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

        // Transfer back the ERC20 tokens.
        erc20Token.safeTransfer(msg.sender, _amount);

        // Remove lenders from list if needed.
        if (
            market[_cErc20Address].lendingBalanceOf[msg.sender].onComp <
            market[_cErc20Address].thresholds[1]
        ) market[_cErc20Address].lendersOnComp.remove(msg.sender);
        if (
            market[_cErc20Address].lendingBalanceOf[msg.sender].onMorpho <
            market[_cErc20Address].thresholds[2]
        ) market[_cErc20Address].lendersOnMorpho.remove(msg.sender);
    }

    /** @dev Allows a borrower to provide collateral in ETH.
     */
    function provideCollateral(address _cErc20Address)
        external
        payable
        nonReentrant
    {
        require(msg.value > 0, "Amount cannot be 0.");
        ICEth cEthToken = ICEth(cEthAddress);
        // Transfer ETH to Morpho.
        payable(address(this)).transfer(msg.value);
        // Supply them to Compound.
        _supplyEthToComp(msg.value); // Revert on error.
        // Update the collateral balance of the sender in cETH.
        market[_cErc20Address].collateralBalanceOf[msg.sender] += msg.value.div(
            cEthToken.exchangeRateCurrent()
        );
    }

    /** @dev Allows a borrower to redeem her collateral in ETH.
     *  @param _amount The amount in ETH to get back.
     */
    function redeemCollateral(address _cErc20Address, uint256 _amount)
        external
        nonReentrant
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        ICEth cEthToken = ICEth(cEthAddress);
        uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountInCEth = _amount.div(cEthExchangeRate);
        require(
            amountInCEth <=
                market[_cErc20Address].collateralBalanceOf[msg.sender],
            "Must redeem less than collateral."
        );

        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 borrowedAmount = market[_cErc20Address]
            .borrowingBalanceOf[msg.sender]
            .onComp
            .mul(borrowIndex) +
            market[_cErc20Address].borrowingBalanceOf[msg.sender].onMorpho.mul(
                mExchangeRate
            );
        uint256 collateralRequiredInEth = getCollateralRequired(
            borrowedAmount,
            collateralFactor,
            _cErc20Address,
            cEthAddress
        );
        uint256 collateralRequiredInCEth = collateralRequiredInEth.div(
            cEthExchangeRate
        );
        uint256 collateralAfterInCEth = market[_cErc20Address]
            .collateralBalanceOf[msg.sender] - amountInCEth;
        require(
            collateralAfterInCEth >= collateralRequiredInCEth,
            "Not enough collateral to maintain position."
        );

        _redeemEthFromComp(_amount, false); // Revert on error.
        market[_cErc20Address].collateralBalanceOf[msg.sender] -= amountInCEth; // In cToken.
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(
        address _cErc20Address,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        (
            uint256 collateralInEth,
            uint256 collateralRequiredInEth
        ) = getAccountLiquidity(_cErc20Address, _borrower);
        require(
            collateralInEth < collateralRequiredInEth,
            "Borrower position cannot be liquidated."
        );
        require(allowed);
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        ICEth cEthToken = ICEth(cEthAddress);
        uint256 mExchangeRate = updateCurrentExchangeRate(_cErc20Address);
        _repay(_cErc20Address, _borrower, _amount);
        // Calculate the amount of token to seize from collateral.
        uint256 ethPriceMantissa = compoundOracle.getUnderlyingPrice(
            cEthAddress
        );
        uint256 underlyingPriceMantissa = compoundOracle.getUnderlyingPrice(
            _cErc20Address
        );
        require(
            ethPriceMantissa != 0 && underlyingPriceMantissa != 0,
            "Oracle failed."
        );

        // Calculate separately to avoid call stack too deep.
        uint256 numerator = _amount
            .mul(underlyingPriceMantissa)
            .mul(collateralInEth)
            .mul(liquidationIncentive);
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 totalBorrowingBalance = market[_cErc20Address]
            .borrowingBalanceOf[_borrower]
            .onComp
            .mul(borrowIndex) +
            borrowingBalanceOf[_borrower].onMorpho.mul(mExchangeRate);
        uint256 denominator = totalBorrowingBalance.mul(ethPriceMantissa);
        uint256 ethAmountToSeize = numerator.div(denominator);
        uint256 cEthAmountToSeize = ethAmountToSeize.div(
            cEthToken.exchangeRateCurrent()
        );
        require(
            cEthAmountToSeize <=
                market[_cErc20Address].collateralBalanceOf[_borrower],
            "Cannot get more than collateral balance of borrower."
        );
        market[_cErc20Address].collateralBalanceOf[
            _borrower
        ] -= cEthAmountToSeize;
        _redeemEthFromComp(ethAmountToSeize, false); // Revert on error.
        payable(msg.sender).transfer(ethAmountToSeize);
    }

    /** @dev Updates the collateral factor related to cToken.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     */
    function updateCollateralFactor(address _cErc20Address) external {
        (, collateralFactor, ) = comptroller.markets(_cErc20Address);
    }

    /* Public */

    /** @dev Returns the collateral and the collateral required for the `_borrower`.
     *  @param _cErc20Address The address of the market the user wants to enter.
     *  @param _borrower The address of `_borrower`.
     *  @return collateralInEth The collateral of the `_borrower` in ETH.
     *  @return collateralRequiredInEth The collateral required of the `_borrower` in ETH.
     */
    function getAccountLiquidity(address _cErc20Address, address _borrower)
        public
        returns (uint256 collateralInEth, uint256 collateralRequiredInEth)
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        ICEth cEthToken = ICEth(CETH_ADDRESS);
        uint256 borrowIndex = cErc20Token.borrowIndex();

        // Calculate total borrowing balance.
        uint256 borrowedAmount = market[_cErc20Address]
            .borrowingBalanceOf[_borrower]
            .onComp
            .mul(borrowIndex) +
            market[_cErc20Address].borrowingBalanceOf[_borrower].onMorpho.mul(
                updateCurrentExchangeRate()
            );
        collateralRequiredInEth = getCollateralRequired(
            borrowedAmount,
            collateralFactor,
            _cErc20Address,
            cEthAddress
        );
        collateralInEth = market[_cErc20Address]
            .collateralBalanceOf[_borrower]
            .mul(cEthToken.exchangeRateCurrent());
    }

    /** @dev Returns the collateral required for the given parameters.
     *  @param _borrowedAmountInUnderlying The amount of underlying tokens borrowed.
     *  @param _collateralFactor The collateral factor linked to the token borrowed.
     *  @param _borrowedCTokenAddress The address of the cToken linked to the token borrowed.
     *  @param _collateralCTokenAddress The address of the cToken linked to the token in collateral.
     *  @return collateralRequired The collateral required of the `_borrower`.
     */
    function getCollateralRequired(
        uint256 _borrowedAmountInUnderlying,
        uint256 _collateralFactor,
        address _borrowedCTokenAddress,
        address _collateralCTokenAddress
    ) public view returns (uint256) {
        uint256 borrowedAssetPriceMantissa = compoundOracle.getUnderlyingPrice(
            _borrowedCTokenAddress
        );
        uint256 collateralAssetPriceMantissa = compoundOracle
            .getUnderlyingPrice(_collateralCTokenAddress);
        require(
            borrowedAssetPriceMantissa != 0 &&
                collateralAssetPriceMantissa != 0,
            "Oracle failed"
        );
        return
            _borrowedAmountInUnderlying
                .mul(borrowedAssetPriceMantissa)
                .div(collateralAssetPriceMantissa)
                .div(_collateralFactor);
    }

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`currentExchangeRate`).
     */
    function updateBPY(address _cErc20Address) public {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        // Update BPY.
        uint256 lendBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        BPY = Math.average(lendBPY, borrowBPY);

        // Update currentExchangeRate.
        updateCurrentExchangeRate();
    }

    /** @dev Updates the current exchange rate, taking into the account block percentage yield since the last time it has been updated.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateCurrentExchangeRate() public returns (uint256) {
        // Update currentExchangeRate.
        uint256 currentBlock = block.number;
        uint256 numberOfBlocksSinceLastUpdate = currentBlock -
            lastUpdateBlockNumber;

        uint256 newCurrentExchangeRate = currentExchangeRate.mul(
            (1e18 + BPY).pow(
                PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
            )
        );
        currentExchangeRate = newCurrentExchangeRate;

        // Update lastUpdateBlockNumber.
        lastUpdateBlockNumber = currentBlock;

        return newCurrentExchangeRate;
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
        erc20Token.transferFrom(msg.sender, address(this), _amount);
        uint256 mExchangeRate = updateCurrentExchangeRate();

        if (market[_cErc20Address].borrowingBalanceOf[_borrower].onComp > 0) {
            uint256 onCompInUnderlying = market[_cErc20Address]
                .borrowingBalanceOf[_borrower]
                .onComp
                .mul(cErc20Token.borrowIndex());

            if (_amount <= onCompInUnderlying) {
                // Repay Compound.
                erc20Token.safeApprove(_cErc20Address, _amount);
                cErc20Token.repayBorrow(_amount);
                markets[_cErc20Address]
                    .borrowingBalanceOf[_borrower]
                    .onComp -= _amount.div(cErc20Token.borrowIndex()); // In cdUnit.
            } else {
                // Repay Compound first.
                erc20Token.safeApprove(cErc20Address, onCompInUnderlying);
                cErc20Token.repayBorrow(onCompInUnderlying); // Revert on error.

                // Then, move the remaining liquidity to Compound.
                uint256 remainingToSupplyToComp = _amount - onCompInUnderlying; // In underlying.
                market[_cErc20Address]
                    .borrowingBalanceOf[_borrower]
                    .onMorpho -= remainingToSupplyToComp.div(mExchangeRate);
                market[_cErc20Address]
                    .borrowingBalanceOf[_borrower]
                    .onComp -= onCompInUnderlying.div(
                    cErc20Token.borrowIndex()
                ); // Since the borrowIndex is updated after a repay.
                _moveLendersFromMorphoToComp(
                    _cErc20Address,
                    remainingToSupplyToComp,
                    _borrower
                ); // Revert on error.

                if (remainingToSupplyToComp > 0)
                    _supplyErc20ToComp(_cErc20Address, remainingToSupplyToComp);
            }
        } else {
            _moveLendersFromMorphoToComp(_cErc20Address, _amount, _borrower);
            market[_cErc20Address]
                .borrowingBalanceOf[_borrower]
                .onMorpho -= _amount.div(mExchangeRate); // In mUnit.
            _supplyErc20ToComp(_cErc20Address, _amount);
        }

        // Remove borrower from lists if needed.
        if (
            market[_cErc20Address].borrowingBalanceOf[_borrower].onComp <
            market[_cErc20Address].thresholds[1]
        ) market[_cErc20Address].borrowersOnComp.remove(_borrower);
        if (
            market[_cErc20Address].borrowingBalanceOf[_borrower].onMorpho <
            market[_cErc20Address].thresholds[2]
        ) market[_cErc20Address].borrowersOnMorpho.remove(_borrower);
    }

    /** @dev Supplies ETH to Compound.
     *  @param _amount The amount in ETH to supply.
     */
    function _supplyEthToComp(uint256 _amount) internal {
        ICEth cEthToken = ICEth(cEthAddress);
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount Amount in ERC20 tokens to supply.
     */
    function _supplyErc20ToComp(address _cErc20Address, uint256 _amount)
        internal
    {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        IERC20 erc20Token = IERC20(cErc20Token.underlying());
        // Approve transfer on the ERC20 contract.
        erc20Token.safeApprove(_cErc20Address, _amount);
        // Mint cTokens.
        require(cErc20Token.mint(_amount) == 0, "cToken minting failed.");
    }

    /** @dev Redeems ERC20 tokens from Compound.
     *  @dev If `_redeemType` is true pass cToken as argument, else pass ERC20 tokens.
     *  @param _cErc20Address The address of the market the user wants to interact with.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     */
    function _redeemErc20FromComp(
        address _cErc20Address,
        uint256 _amount,
        bool _redeemType
    ) internal {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);
        uint256 result;
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount.
            result = cErc20Token.redeem(_amount);
        } else {
            // Retrieve your asset based on a ERC20 tokens amount.
            result = cErc20Token.redeemUnderlying(_amount);
        }
        require(result == 0, "Redeem ERC20 on Compound failed.");
    }

    /** @dev Redeems ETH from Compound.
     *  @dev If `_redeemType` is true pass cETH as argument, else pass ETH.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     */
    function _redeemEthFromComp(uint256 _amount, bool _redeemType) internal {
        ICEth cEthToken = ICEth(cEthAddress);
        uint256 result;
        if (_redeemType == true) {
            // Retrieve your asset based on a cETH amount.
            result = cEthToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an ETH amount.
            result = cEthToken.redeemUnderlying(_amount);
        }
        require(result == 0, "Redeem ETH on Compound failed.");
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
        remainingToMove = _amount; // In underlying.
        uint256 mExchangeRate = currentExchangeRate;
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        address lender = markets[_cErc20Address].lendersOnComp.getHead();
        uint256 i;
        while (
            remainingToMove > 0 &&
            i < market[_cErc20Address].lendersOnComp.length()
        ) {
            if (lender != _lenderToAvoid) {
                uint256 onComp = market[_cErc20Address]
                    .lendingBalanceOf[lender]
                    .onComp; // In cToken.

                if (onComp > 0) {
                    uint256 amountToMove = Math.min(
                        onComp.mul(cExchangeRate),
                        remainingToMove
                    ); // In underlying.
                    remainingToMove -= amountToMove;
                    market[_cErc20Address]
                        .lendingBalanceOf[lender]
                        .onComp -= amountToMove.div(cExchangeRate); // In cToken.
                    market[_cErc20Address]
                        .lendingBalanceOf[lender]
                        .onMorpho += amountToMove.div(mExchangeRate); // In mUnit.

                    // Update lists if needed.
                    if (
                        market[_cErc20Address].lendingBalanceOf[lender].onComp <
                        market[_cErc20Address].thresholds[1]
                    ) market[_cErc20Address].lendersOnComp.remove(lender);
                    if (
                        market[_cErc20Address]
                            .lendingBalanceOf[lender]
                            .onMorpho >= market[_cErc20Address].thresholds[2]
                    ) market[_cErc20Address].lendersOnMorpho.addTail(lender);
                }
            } else {
                lender = market[_cErc20Address].lendersOnComp.getNext(lender);
            }
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
        uint256 remainingToMove = _amount; // In underlying.
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 mExchangeRate = currentExchangeRate;
        address lender = markets[_cErc20Address].lendersOnMorpho.getHead();
        uint256 i;
        while (
            remainingToMove > 0 &&
            i < market[_cErc20Address].lendersOnMorpho.length()
        ) {
            if (lender != _lenderToAvoid) {
                uint256 onMorpho = market[_cErc20Address]
                    .lendingBalanceOf[lender]
                    .onMorpho; // In mUnit.

                if (onMorpho > 0) {
                    uint256 amountToMove = Math.min(
                        onMorpho.mul(mExchangeRate),
                        remainingToMove
                    ); // In underlying.
                    remainingToMove -= amountToMove; // In underlying.
                    market[_cErc20Address]
                        .lendingBalanceOf[lender]
                        .onComp += amountToMove.div(cExchangeRate); // In cToken.
                    market[_cErc20Address]
                        .lendingBalanceOf[lender]
                        .onMorpho -= amountToMove.div(mExchangeRate); // In mUnit.

                    // Update lists if needed.
                    if (
                        market[_cErc20Address]
                            .lendingBalanceOf[lender]
                            .onComp >= market[_cErc20Address].thresholds[1]
                    ) market[_cErc20Address].lendersOnComp.addTail(lender);
                    if (
                        market[_cErc20Address]
                            .lendingBalanceOf[lender]
                            .onMorpho < market[_cErc20Address].thresholds[2]
                    ) market[_cErc20Address].lendersOnMorpho.remove(lender);
                }
            } else {
                lender = markets[_cErc20Address].lendersOnMorpho.getNext(
                    lender
                );
            }
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
        uint256 mExchangeRate = currentExchangeRate;
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 i;
        while (
            remainingToMatch > 0 &&
            i < market[_cErc20Address].borrowersOnMorpho.length()
        ) {
            address borrower = market[_cErc20Address]
                .borrowersOnMorpho
                .getHead();

            if (
                market[_cErc20Address].borrowingBalanceOf[borrower].onMorpho > 0
            ) {
                uint256 toMatch = Math.min(
                    market[_cErc20Address]
                        .borrowingBalanceOf[borrower]
                        .onMorpho
                        .mul(mExchangeRate),
                    remainingToMatch
                ); // In underlying.

                remainingToMatch -= toMatch;
                market[_cErc20Address]
                    .borrowingBalanceOf[borrower]
                    .onComp += toMatch.div(borrowIndex);
                market[_cErc20Address]
                    .borrowingBalanceOf[borrower]
                    .onMorpho -= toMatch.div(mExchangeRate);

                // Update lists if needed.
                if (
                    market[_cErc20Address]
                        .borrowingBalanceOf[borrower]
                        .onComp >= market[_cErc20Address].thresholds[1]
                ) market[_cErc20Address].borrowersOnComp.addTail(borrower);
                if (
                    market[_cErc20Address]
                        .borrowingBalanceOf[borrower]
                        .onMorpho < market[_cErc20Address].thresholds[2]
                ) market[_cErc20Address].borrowersOnMorpho.remove(borrower);
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
        uint256 mExchangeRate = currentExchangeRate;
        uint256 borrowIndex = cErc20Token.borrowIndex();
        uint256 i;
        while (
            remainingToMatch > 0 &&
            i < market[_cErc20Address].borrowersOnComp.length()
        ) {
            address borrower = market[_cErc20Address].borrowersOnComp.getHead();

            if (
                market[_cErc20Address].borrowingBalanceOf[borrower].onComp > 0
            ) {
                uint256 onCompInUnderlying = market[_cErc20Address]
                    .borrowingBalanceOf[borrower]
                    .onComp
                    .mul(borrowIndex);
                uint256 toMatch = Math.min(
                    onCompInUnderlying,
                    remainingToMatch
                ); // In underlying.

                remainingToMatch -= toMatch;
                market[_cErc20Address]
                    .borrowingBalanceOf[borrower]
                    .onComp -= toMatch.div(borrowIndex);
                market[_cErc20Address]
                    .borrowingBalanceOf[borrower]
                    .onMorpho += toMatch.div(mExchangeRate);

                markets[_cErc20Address].borrowersOnMorpho.addTail(borrower);
                // Update lists if needed.
                if (
                    market[_cErc20Address].borrowingBalanceOf[borrower].onComp <
                    market[_cErc20Address].thresholds[1]
                ) market[_cErc20Address].borrowersOnComp.remove(borrower);
                if (
                    market[_cErc20Address]
                        .borrowingBalanceOf[borrower]
                        .onMorpho >= market[_cErc20Address].thresholds[2]
                ) market[_cErc20Address].borrowersOnMorpho.addTail(borrower);
            }
            i++;
        }
    }

    // This is needed to receive ETH when calling `_redeemEthFromComp`
    receive() external payable {}

    /* Morpho markets management */

    function createMarkets(address[] memory _cTokensAddresses) public {
        address[] memory marketsToEnter = new address[](
            _cTokensAddresses.length
        );
        for (uint256 k = 0; k < _cTokensAddresses.length; k++) {
            marketsToEnter[k] = _cTokensAddresses[k];
        }
        comptroller.enterMarkets(marketsToEnter);
        for (uint256 k = 0; k < _cTokensAddresses.length; k++) {
            market[_cTokensAddresses[k]].isListed = true;
            market[_cTokensAddresses[k]].collateralFactorMantissa = 75e16;
            updateBPY(_cTokensAddresses[k]);
        }
    }

    function listMarket(address _cTokenAddress) public {
        market[_cTokenAddress].isListed = true;
    }

    function unlistMarket(address _cTokenAddress) public {
        market[_cTokenAddress].isListed = false;
    }

    /* Functions authorizations */

    function lendAuthorization(
        address _cErc20Token,
        address,
        uint256
    ) internal view returns (bool) {
        // check if market is listed
        require(market[_cErc20Token].isListed, "Market not listed");
        return true;
    }

    function borrowAuthorization(
        address _cErc20Token,
        address _user,
        uint256 _amount
    ) internal returns (bool) {
        // check if market is listed
        require(market[_cErc20Token].isListed, "Market not listed");
        // check if the user has enough collateral
        uint256 debt;
        // TODO prevent dust borrowing
        for (uint256 k = 0; k < enteredMarketsAsBorrowerOf[_user].length; k++) {
            address _cErc20Address = enteredMarketsAsBorrowerOf[_user][k];
            ICErc20 cErc20Token = ICErc20(_cErc20Address);
            uint256 mExchangeRate = updateCurrentExchangeRate();
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            debt +=
                market[_cErc20Address].borrowingBalanceOf[_user].onComp.mul(
                    mExchangeRate
                ) +
                market[_cErc20Address].borrowingBalanceOf[_user].onMorpho.mul(
                    cExchangeRate
                );
        }
        uint256 maxDebt;
        for (
            uint256 k = 0;
            k < enteredMarketsForCollateral[_user].length;
            k++
        ) {
            address _cErc20Address = enteredMarketsForCollateral[_user][k];
            ICErc20 cErc20Token = ICErc20(_cErc20Address);
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            maxDebt +=
                market[_cErc20Address].collateralBalanceOf[_user].mul(
                    cExchangeRate
                ) *
                market[_cErc20Address].collateralFactorMantissa;
        }
        require(_amount < maxDebt - debt, "Not enough collateral");
        return true;
    }

    function withdrawAuthorization(
        address _cErc20Token,
        address _user,
        uint256 _amount
    ) internal returns (bool) {
        // check if market is listed
        require(market[_cErc20Token].isListed, "Market not listed");
        // check if the user entered this market as a lender
        require(
            market[_cErc20Token].lendersOnComp.contains(_user) ||
                market[_cErc20Token].lendersOnMorpho.contains(_user)
        );
        // check if the user has enough collateral
        uint256 debt;
        for (uint256 k = 0; k < enteredMarketsAsBorrowerOf[_user].length; k++) {
            address _cErc20Address = enteredMarketsAsBorrowerOf[_user][k];
            ICErc20 cErc20Token = ICErc20(_cErc20Address);
            uint256 mExchangeRate = updateCurrentExchangeRate();
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            debt +=
                market[_cErc20Address].borrowingBalanceOf[_user].onComp.mul(
                    cExchangeRate
                ) +
                market[_cErc20Address].borrowingBalanceOf[_user].onMorpho.mul(
                    mExchangeRate
                );
        }
        uint256 maxDebt;
        for (
            uint256 k = 0;
            k < enteredMarketsForCollateral[_user].length;
            k++
        ) {
            address _cErc20Address = enteredMarketsForCollateral[_user][k];
            ICErc20 cErc20Token = ICErc20(_cErc20Address);
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            maxDebt +=
                market[_cErc20Address].collateralBalanceOf[_user].mul(
                    cExchangeRate
                ) *
                market[_cErc20Address].collateralFactorMantissa;
        }
        require(_amount < maxDebt - debt, "Not enough collateral");

        return true;
    }

    function repayAuthorization(
        address _cErc20Token,
        address _user,
        uint256
    ) internal view returns (bool) {
        // check if market is listed
        require(market[_cErc20Token].isListed, "Market not listed");
        // check if the user entered this market as a borrower
        require(
            market[_cErc20Token].borrowersOnComp.contains(_user) ||
                market[_cErc20Token].borrowersOnMorpho.contains(_user)
        );
        return true;
    }
}
