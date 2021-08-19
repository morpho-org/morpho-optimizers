pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, ICEth, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with ETH as collateral and a cERC20 token as lending/borrowing asset.
 */
contract CompoundModule is ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
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
        uint256 onComp; // In underlying.
    }

    /* Storage */

    mapping(address => LendingBalance) public lendingBalanceOf; // Lending balance of user (ERC20/cERC20).
    mapping(address => BorrowingBalance) public borrowingBalanceOf; // Borrowing balance of user (ERC20).
    mapping(address => uint256) public collateralBalanceOf; // Collateral balance of user (cETH).
    EnumerableSet.AddressSet private lenders; // Lenders on Morpho.
    EnumerableSet.AddressSet private borrowersOnMorpho; // Borrowers on Morpho.
    EnumerableSet.AddressSet private borrowersOnComp; // Borrowers on Compound.

    uint256 public BPY; // Block Percentage Yield ("midrate").
    uint256 public collateralFactor = 75e16; // Collateral Factor related to cToken.
    uint256 public liquidationIncentive = 1.1e18; // Incentive for liquidators in percentage (110%).
    uint256 public currentExchangeRate = 1e18; // current exchange rate from mUnit to underlying.
    uint256 public lastUpdateBlockNumber; // Last time currentExchangeRate was updated.

    // For now these variables are set in the storage not in constructor:
    address public constant PROXY_COMPTROLLER_ADDRESS =
        0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address payable public constant CETH_ADDRESS =
        payable(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public cErc20Address;

    IComptroller public comptroller;
    ICompoundOracle public compoundOracle;
    ICEth public cEthToken;
    ICErc20 public cErc20Token;
    IERC20 public erc20Token;

    /* Contructor */

    constructor(address _cErc20Address) {
        comptroller = IComptroller(PROXY_COMPTROLLER_ADDRESS);
        address[] memory markets = new address[](2);
        markets[0] = CETH_ADDRESS;
        markets[1] = _cErc20Address;
        comptroller.enterMarkets(markets);
        cEthToken = ICEth(CETH_ADDRESS);
        cErc20Address = _cErc20Address;
        cErc20Token = ICErc20(_cErc20Address);
        address compoundOracleAddress = comptroller.oracle();
        compoundOracle = ICompoundOracle(compoundOracleAddress);
        erc20Token = IERC20(cErc20Token.underlying());
        lastUpdateBlockNumber = block.number;
        updateBPY();
    }

    /* External */

    /** @dev Lends ERC20 tokens.
     *  @param _amount The amount to lend in ERC20 tokens.
     */
    function lend(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount cannot be 0.");
        erc20Token.transferFrom(msg.sender, address(this), _amount);
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            uint256 mExchangeRate = _updateCurrentExchangeRate();
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                _amount
            ); // In underlying.
            // Repay Compound.
            // TODO: verify that not too much is sent to Compound.
            uint256 toRepay = _amount - remainingToSupplyToComp;
            cErc20Token.repayBorrow(toRepay); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho += toRepay.div(mExchangeRate); // In mUnit.
            lendingBalanceOf[msg.sender].onComp += remainingToSupplyToComp.div(
                cExchangeRate
            ); // In cToken.
            if (remainingToSupplyToComp > 0)
                _supplyErc20ToComp(remainingToSupplyToComp); // Revert on error.
        } else {
            lendingBalanceOf[msg.sender].onComp += _amount.div(cExchangeRate); // In cToken.
            _supplyErc20ToComp(_amount); // Revert on error.
        }
    }

    /** @dev Stakes cTokens.
     *  @param _amount The amount to stake in cTokens.
     */
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount cannot be 0.");
        cErc20Token.transferFrom(msg.sender, address(this), _amount);
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            uint256 mExchangeRate = _updateCurrentExchangeRate();
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            uint256 amountInUnderlying = _amount.mul(cExchangeRate);
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = _moveBorrowersFromCompToMorpho(
                amountInUnderlying
            ); // In underlying.
            _redeemErc20FromComp(remainingToSupplyToComp, false);
            // Repay Compound.
            // TODO: verify that not too much is sent to Compound.
            uint256 toRepay = amountInUnderlying - remainingToSupplyToComp;
            cErc20Token.repayBorrow(toRepay); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho += toRepay.div(mExchangeRate); // In mUnit.
            lendingBalanceOf[msg.sender].onComp += remainingToSupplyToComp.div(
                cExchangeRate
            ); // In cToken.
        } else {
            lendingBalanceOf[msg.sender].onComp += _amount; // In cToken.
        }
    }

    /** @dev Borrows ERC20 tokens.
     *  @param _amount The amount to borrow in ERC20 tokens.
     */
    function borrow(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount cannot be 0.");
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        uint256 amountBorrowedAfter = _amount +
            borrowingBalanceOf[msg.sender].onComp +
            borrowingBalanceOf[msg.sender].onMorpho.mul(mExchangeRate);
        // Calculate the collateral required.
        uint256 collateralRequiredInEth = getCollateralRequired(
            amountBorrowedAfter,
            collateralFactor,
            cErc20Address,
            CETH_ADDRESS
        );
        uint256 collateralRequiredInCEth = collateralRequiredInEth.div(
            cEthToken.exchangeRateCurrent()
        );
        // Prevent to borrow dust without collateral.
        require(collateralRequiredInCEth > 0, "Borrowing is too low.");
        // Check if borrower has enough collateral.
        require(
            collateralRequiredInCEth <= collateralBalanceOf[msg.sender],
            "Not enough collateral."
        );
        uint256 remainingToBorrowOnComp = _moveLendersFromCompToMorpho(
            _amount,
            msg.sender
        ); // In underlying.
        uint256 toRedeem = _amount - remainingToBorrowOnComp;
        borrowingBalanceOf[msg.sender].onMorpho += toRedeem.div(mExchangeRate); // In mUnit.
        // If not enough cTokens on Morpho, we must borrow it on Compound.
        if (remainingToBorrowOnComp > 0) {
            // TODO: round superior to avoid floating issues.
            require(
                cErc20Token.borrow(remainingToBorrowOnComp) == 0,
                "Borrow on Compound failed."
            );
            borrowingBalanceOf[msg.sender].onComp += remainingToBorrowOnComp; // In underlying.
            borrowersOnComp.add(msg.sender);
            if (remainingToBorrowOnComp != _amount)
                borrowersOnMorpho.add(msg.sender);
        }
        if (toRedeem > 0) _redeemErc20FromComp(toRedeem, false); // Revert on error.
        // Transfer ERC20 tokens to borrower.
        erc20Token.safeTransfer(msg.sender, _amount);
    }

    /** @dev Repays debt of the user.
     *  @param _amount The amount in ERC20 tokens to repay.
     */
    function repay(uint256 _amount) external nonReentrant {
        _repay(msg.sender, _amount);
    }

    /** @dev Withdraws ERC20 tokens from lending.
     *  @param _amount The amount in tokens to withdraw from lending.
     */
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount cannot be 0.");
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 amountOnCompInUnderlying = lendingBalanceOf[msg.sender]
            .onComp
            .mul(cExchangeRate);
        if (_amount <= amountOnCompInUnderlying) {
            // Simple case where we can directly withdraw unused liquidity on Compound.
            lendingBalanceOf[msg.sender].onComp -= _amount.div(cExchangeRate); // In cToken.
            _redeemErc20FromComp(_amount, false);
        } else {
            // We take all the unused liquidy first.
            lendingBalanceOf[msg.sender].onComp = 0;
            _redeemErc20FromComp(amountOnCompInUnderlying, false); // Revert on error.
            // And search for the remaining liquidity.
            uint256 remainingToWithdraw = _amount - amountOnCompInUnderlying; // In underlying.
            lendingBalanceOf[msg.sender].onMorpho -= remainingToWithdraw.div(
                mExchangeRate
            ); // In mUnit.
            uint256 cTokenContractBalanceInUnderlying = cErc20Token
                .balanceOf(address(this))
                .mul(cExchangeRate);
            if (remainingToWithdraw <= cTokenContractBalanceInUnderlying) {
                // There is enough cTokens in the contract to use.
                _moveLendersFromCompToMorpho(remainingToWithdraw, msg.sender);
            } else {
                // The contract does not have enough cTokens for the withdraw.
                // First, we use all the cTokens in the contract.
                _moveLendersFromCompToMorpho(
                    cTokenContractBalanceInUnderlying,
                    msg.sender
                );
                // Then, we put borrowers on Compound.
                remainingToWithdraw -= cTokenContractBalanceInUnderlying;
                remainingToWithdraw -= _moveBorrowersFromMorphoToComp(
                    remainingToWithdraw
                );
                // Finally, we borrow directly on Compound to search the remaining liquidity if any.
                require(
                    cErc20Token.borrow(remainingToWithdraw) == 0,
                    "Borrow on Compound failed."
                );
            }
        }
        // Transfer back the ERC20 tokens.
        erc20Token.safeTransfer(msg.sender, _amount);
        // If lender has no lending at all, then remove her from `lenders`.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            lenders.remove(msg.sender);
        }
    }

    /** @dev Allows a lender to unstake its cToken.
     *  @param _amount Amount in cToken to unstake.
     */
    function unstake(uint256 _amount) external nonReentrant {
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        if (_amount <= lendingBalanceOf[msg.sender].onComp) {
            lendingBalanceOf[msg.sender].onComp -= _amount;
        } else {
            uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
            uint256 remainingToUnstakeInUnderlying = (_amount -
                lendingBalanceOf[msg.sender].onComp).mul(cExchangeRate);
            lendingBalanceOf[msg.sender].onComp = 0;
            lendingBalanceOf[msg.sender]
                .onMorpho -= remainingToUnstakeInUnderlying.div(mExchangeRate); // In mUnit.
            uint256 cTokenContractBalanceInUnderlying = cErc20Token
                .balanceOf(address(this))
                .mul(cExchangeRate);
            if (
                remainingToUnstakeInUnderlying <=
                cTokenContractBalanceInUnderlying
            ) {
                _moveLendersFromCompToMorpho(
                    remainingToUnstakeInUnderlying,
                    msg.sender
                );
            } else {
                _moveLendersFromCompToMorpho(
                    cTokenContractBalanceInUnderlying,
                    msg.sender
                );
                remainingToUnstakeInUnderlying -= cTokenContractBalanceInUnderlying;
                remainingToUnstakeInUnderlying -= _moveBorrowersFromMorphoToComp(
                    remainingToUnstakeInUnderlying
                );
                require(
                    cErc20Token.borrow(remainingToUnstakeInUnderlying) == 0,
                    "Borrow on Compound failed."
                );
            }
        }
        cErc20Token.transfer(msg.sender, _amount);
        // If lender has no lending at all, then remove her from `lenders`.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            lenders.remove(msg.sender);
        }
    }

    /** @dev Allows a borrower to provide collateral in ETH.
     */
    function provideCollateral() external payable nonReentrant {
        require(msg.value > 0, "Amount cannot be 0.");
        // Transfer ETH to Morpho.
        payable(address(this)).transfer(msg.value);
        // Supply them to Compound.
        _supplyEthToComp(msg.value); // Revert on error.
        // Update the collateral balance of the sender in cETH.
        collateralBalanceOf[msg.sender] += msg.value.div(
            cEthToken.exchangeRateCurrent()
        );
    }

    /** @dev Allows a borrower to redeem her collateral in ETH.
     *  @param _amount The amount in ETH to get back.
     */
    function redeemCollateral(uint256 _amount) external nonReentrant {
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountInCEth = _amount.div(cEthExchangeRate);
        require(
            amountInCEth <= collateralBalanceOf[msg.sender],
            "Must redeem less than collateral."
        );
        uint256 borrowedAmount = borrowingBalanceOf[msg.sender].onComp +
            borrowingBalanceOf[msg.sender].onMorpho.mul(mExchangeRate);
        uint256 collateralRequiredInEth = getCollateralRequired(
            borrowedAmount,
            collateralFactor,
            cErc20Address,
            CETH_ADDRESS
        );
        uint256 collateralRequiredInCEth = collateralRequiredInEth.div(
            cEthExchangeRate
        );
        uint256 collateralAfterInCEth = collateralBalanceOf[msg.sender] -
            amountInCEth;
        require(
            collateralAfterInCEth >= collateralRequiredInCEth,
            "Not enough collateral to maintain position."
        );
        _redeemEthFromComp(_amount, false); // Revert on error.
        collateralBalanceOf[msg.sender] -= amountInCEth; // In cToken.
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in ERC20 tokens.
     */
    function liquidate(address _borrower, uint256 _amount)
        external
        nonReentrant
    {
        (
            uint256 collateralInEth,
            uint256 collateralRequiredInEth
        ) = getAccountLiquidity(_borrower);
        require(
            collateralInEth < collateralRequiredInEth,
            "Borrower position cannot be liquidated."
        );
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        _repay(_borrower, _amount);
        // Calculate the amount of token to seize from collateral.
        uint256 ethPriceMantissa = compoundOracle.getUnderlyingPrice(
            CETH_ADDRESS
        );
        uint256 underlyingPriceMantissa = compoundOracle.getUnderlyingPrice(
            cErc20Address
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
        uint256 totalBorrowingBalance = borrowingBalanceOf[_borrower].onComp +
            borrowingBalanceOf[_borrower].onMorpho.mul(mExchangeRate);
        uint256 denominator = totalBorrowingBalance.mul(ethPriceMantissa);
        uint256 ethAmountToSeize = numerator.div(denominator);
        uint256 cEthAmountToSeize = ethAmountToSeize.div(
            cEthToken.exchangeRateCurrent()
        );
        require(
            cEthAmountToSeize <= collateralBalanceOf[_borrower],
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceOf[_borrower] -= cEthAmountToSeize;
        _redeemEthFromComp(ethAmountToSeize, false); // Revert on error.
        payable(msg.sender).transfer(ethAmountToSeize);
    }

    /** @dev Updates the collateral factor related to cToken.
     */
    function updateCollateralFactor() external {
        (, collateralFactor, ) = comptroller.markets(cErc20Address);
    }

    /* Public */

    /** @dev Returns the collateral and the collateral required for the `_borrower`.
     *  @param _borrower The address of `_borrower`.
     *  @return collateralInEth The collateral of the `_borrower` in ETH.
     *  @return collateralRequiredInEth The collateral required of the `_borrower` in ETH.
     */
    function getAccountLiquidity(address _borrower)
        public
        returns (uint256 collateralInEth, uint256 collateralRequiredInEth)
    {
        uint256 borrowedAmount = borrowingBalanceOf[_borrower].onComp +
            borrowingBalanceOf[_borrower].onMorpho.mul(
                _updateCurrentExchangeRate()
            );
        collateralRequiredInEth = getCollateralRequired(
            borrowedAmount,
            collateralFactor,
            cErc20Address,
            CETH_ADDRESS
        );
        collateralInEth = collateralBalanceOf[_borrower].mul(
            cEthToken.exchangeRateCurrent()
        );
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
        // TODO: check overflow/underflow and precision for this calculation.
        return
            _borrowedAmountInUnderlying
                .mul(borrowedAssetPriceMantissa)
                .div(collateralAssetPriceMantissa)
                .div(_collateralFactor);
    }

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`currentExchangeRate`).
     */
    function updateBPY() public {
        // Update BPY.
        uint256 lendBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        BPY = Math.average(lendBPY, borrowBPY);

        // Update currentExchangeRate.
        _updateCurrentExchangeRate();
    }

    /* Internal */

    /** @dev Implements repay logic.
     *  @param _borrower The address of the `_borrower` to repay the borrowing.
     *  @param _amount The amount of ERC20 tokens to repay.
     */
    function _repay(address _borrower, uint256 _amount) internal {
        uint256 mExchangeRate = _updateCurrentExchangeRate();
        if (borrowingBalanceOf[_borrower].onComp > 0) {
            if (_amount <= borrowingBalanceOf[_borrower].onComp) {
                // Repay Compound.
                borrowingBalanceOf[_borrower].onComp -= _amount;
                cErc20Token.repayBorrow(_amount); // Revert on error.
                _supplyErc20ToComp(_amount); // Revert on error.
            } else {
                // Repay Compound first.
                cErc20Token.repayBorrow(borrowingBalanceOf[_borrower].onComp); // Revert on error.
                // Then, move remaining and supply it to Compound.
                uint256 remainingToSupplyToComp = _amount -
                    borrowingBalanceOf[_borrower].onComp; // In underlying.
                borrowingBalanceOf[_borrower]
                    .onMorpho -= remainingToSupplyToComp.div(mExchangeRate);
                borrowingBalanceOf[_borrower].onComp = 0;
                borrowersOnComp.remove(_borrower);
                _moveLendersFromMorphoToComp(
                    remainingToSupplyToComp,
                    _borrower
                );
                if (remainingToSupplyToComp > 0)
                    _supplyErc20ToComp(remainingToSupplyToComp);
            }
        } else {
            _moveLendersFromMorphoToComp(_amount, _borrower);
            borrowingBalanceOf[_borrower].onMorpho -= _amount.div(
                mExchangeRate
            ); // In mUnit.
            _supplyErc20ToComp(_amount);
        }
        if (
            borrowingBalanceOf[_borrower].onMorpho == 0 &&
            borrowingBalanceOf[_borrower].onComp == 0
        ) borrowersOnMorpho.remove(_borrower);
    }

    /** @dev Supplies ETH to Compound.
     *  @param _amount The amount in ETH to supply.
     */
    function _supplyEthToComp(uint256 _amount) internal {
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    /** @dev Supplies ERC20 tokens to Compound.
     *  @param _amount Amount in ERC20 tokens to supply.
     */
    function _supplyErc20ToComp(uint256 _amount) internal {
        // Approve transfer on the ERC20 contract.
        erc20Token.safeApprove(cErc20Address, _amount);
        // Mint cTokens.
        require(cErc20Token.mint(_amount) == 0, "cToken minting failed.");
    }

    /** @dev Redeems ERC20 tokens from Compound.
     *  @dev If `_redeemType` is true pass cToken as argument, else pass ERC20 tokens.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     */
    function _redeemErc20FromComp(uint256 _amount, bool _redeemType) internal {
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
     *  @param _amount The amount to search for in underlying.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     *  @return remainingToMove The remaining liquidity to search for in underlying.
     */
    function _moveLendersFromCompToMorpho(
        uint256 _amount,
        address _lenderToAvoid
    ) internal returns (uint256 remainingToMove) {
        remainingToMove = _amount; // In underlying.
        uint256 mExchangeRate = currentExchangeRate;
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 onComp = lendingBalanceOf[lender].onComp; // In cToken.

                if (onComp > 0) {
                    uint256 amountToMove = Math.min(
                        onComp.mul(cExchangeRate),
                        remainingToMove
                    ); // In underlying.
                    lendingBalanceOf[lender].onComp -= amountToMove.div(
                        cExchangeRate
                    ); // In cToken.
                    lendingBalanceOf[lender].onMorpho += amountToMove.div(
                        mExchangeRate
                    ); // In mUnit.
                    remainingToMove -= amountToMove;
                }
            }
            i++;
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
     *  @param _amount The amount to search for in underlying.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     */
    function _moveLendersFromMorphoToComp(
        uint256 _amount,
        address _lenderToAvoid
    ) internal {
        uint256 remainingToMove = _amount; // In underlying.
        uint256 cExchangeRate = cErc20Token.exchangeRateCurrent();
        uint256 mExchangeRate = currentExchangeRate;
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 used = lendingBalanceOf[lender].onMorpho; // In mUnit.

                if (used > 0) {
                    uint256 amountToMove = Math.min(
                        used.mul(mExchangeRate),
                        remainingToMove
                    ); // In underlying.
                    lendingBalanceOf[lender].onComp += amountToMove.div(
                        cExchangeRate
                    ); // In cToken.
                    lendingBalanceOf[lender].onMorpho -= amountToMove.div(
                        mExchangeRate
                    ); // In mUnit.
                    remainingToMove -= amountToMove; // In underlying.
                }
            }
            i++;
        }
        require(remainingToMove == 0, "Not enough liquidity to unuse.");
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _moveBorrowersFromMorphoToComp(uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        remainingToMatch = _amount;
        uint256 mExchangeRate = currentExchangeRate;
        uint256 i;
        while (remainingToMatch > 0 && i < borrowersOnMorpho.length()) {
            address borrower = borrowersOnMorpho.at(i);

            if (borrowingBalanceOf[borrower].onMorpho > 0) {
                uint256 toMatch = Math.min(
                    borrowingBalanceOf[borrower].onMorpho.mul(mExchangeRate),
                    remainingToMatch
                ); // In underlying.
                remainingToMatch -= toMatch;
                borrowingBalanceOf[borrower].onComp += toMatch;
                borrowingBalanceOf[borrower].onMorpho -= toMatch.div(
                    mExchangeRate
                );
                borrowersOnComp.add(borrower);
                if (borrowingBalanceOf[borrower].onMorpho == 0)
                    borrowersOnMorpho.remove(borrower);
            }
            i++;
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @dev Note: currentExchangeRate must have been upated before calling this function.
     *  @param _amount The amount to match in underlying.
     *  @return remainingToMatch The amount remaining to match in underlying.
     */
    function _moveBorrowersFromCompToMorpho(uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        remainingToMatch = _amount;
        uint256 mExchangeRate = currentExchangeRate;
        uint256 i;
        while (remainingToMatch > 0 && i < borrowersOnComp.length()) {
            address borrower = borrowersOnComp.at(i);

            if (borrowingBalanceOf[borrower].onComp > 0) {
                uint256 toMatch = Math.min(
                    borrowingBalanceOf[borrower].onComp,
                    remainingToMatch
                ); // In underlying.
                remainingToMatch -= toMatch;
                borrowingBalanceOf[borrower].onComp -= toMatch;
                borrowingBalanceOf[borrower].onMorpho += toMatch.div(
                    mExchangeRate
                );
                borrowersOnMorpho.add(borrower);
                if (borrowingBalanceOf[borrower].onComp == 0)
                    borrowersOnComp.remove(borrower);
            }
            i++;
        }
    }

    /** @dev Updates the current exchange rate, taking into the account block percentage yield since the last time it has been updated.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function _updateCurrentExchangeRate() internal returns (uint256) {
        // Update currentExchangeRate.
        uint256 currentBlock = block.number;
        uint256 numberOfBlocksSinceLastUpdate = currentBlock -
            lastUpdateBlockNumber;
        currentExchangeRate = currentExchangeRate.mul(
            (1e18 + BPY).pow(numberOfBlocksSinceLastUpdate)
        );

        // Update lastUpdateBlockNumber.
        lastUpdateBlockNumber = currentBlock;

        return currentExchangeRate;
    }

    // This is needed to receive ETH when calling `_redeemEthFromComp`
    receive() external payable {}
}
