pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOracle.sol";
import {ICErc20, ICEth, IComptroller} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending.
 */
contract CompoundModule {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* Structs */

    struct LendingBalance {
        uint256 onComp; // In cToken.
        uint256 onMorpho; // In underlying Token.
    }

    struct BorrowingBalance {
        uint256 total; // In underlying.
        uint256 onComp; // In underlying.
    }

    /* Storage */

    mapping(address => LendingBalance) public lendingBalanceOf; // Lending balance of user (ETH/cETH).
    mapping(address => BorrowingBalance) public borrowingBalanceOf; // Borrowing balance of user (ETH).
    mapping(address => uint256) public collateralBalanceOf; // Collateral balance of user (cDAI).
    EnumerableSet.AddressSet private lenders; // Lenders on Morpho.
    EnumerableSet.AddressSet private borrowersOnMorpho; // Borrowers on Morpho.
    EnumerableSet.AddressSet private borrowersOnComp; // Borrowers on Compound.
    uint256 public collateralFactor = 75e16; // Collateral Factor related to cETH.
    uint256 public liquidationIncentive = 8000; // Incentive for liquidators in percentage in basis points.

    uint256 public constant DENOMINATOR = 10000; // Denominator for percentage multiplications.
    address public constant PROXY_COMPTROLLER_ADDRESS =
        0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address payable public constant CETH_ADDRESS =
        payable(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI_ADDRESS =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address payable public constant CDAI_ADDRESS =
        payable(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant ORACLE_ADDRESS =
        0xf6688883084DC1467c6F9158A0a9f398E29635BF;

    IComptroller public comptroller = IComptroller(PROXY_COMPTROLLER_ADDRESS);
    ICEth public cEthToken = ICEth(CETH_ADDRESS);
    ICErc20 public cDaiToken = ICErc20(CDAI_ADDRESS);
    IERC20 public daiToken = IERC20(DAI_ADDRESS);
    IOracle public oracle = IOracle(ORACLE_ADDRESS);

    /* External */

    /** @dev Allows someone to lend ETH.
     *  @dev ETH amount is sent through msg.value.
     */
    function lend() external payable {
        require(msg.value > 0, "Amount cannot be 0");
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = (_moveBorrowersFromCompToMorpho(
                msg.value
            ) * 1e18) / cEthExchangeRate;
            // Repay Compound.
            cEthToken.repayBorrow{value: msg.value - remainingToSupplyToComp}(); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                msg.value -
                remainingToSupplyToComp; // In underlying.
            lendingBalanceOf[msg.sender].onComp +=
                (remainingToSupplyToComp * cEthExchangeRate) /
                1e18; // In cToken.
            if (remainingToSupplyToComp > 0)
                _supplyEthToComp(remainingToSupplyToComp);
        } else {
            lendingBalanceOf[msg.sender].onComp +=
                (msg.value * 1e18) /
                cEthExchangeRate; // In cToken.
            _supplyEthToComp(msg.value);
        }
    }

    /** @dev Allows someone to directly stake cETH.
     *  @param _amount The amount to stake in cETH.
     */
    function stake(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        cEthToken.transferFrom(msg.sender, address(this), _amount);
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
            uint256 amountInEth = (_amount * cEthExchangeRate) / 1e18;
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = (_moveBorrowersFromCompToMorpho(
                amountInEth
            ) * 1e18) / cEthExchangeRate;
            _redeemEthFromComp(remainingToSupplyToComp, false);
            // Repay Compound.
            cEthToken.repayBorrow{
                value: amountInEth - remainingToSupplyToComp
            }(); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                ((_amount - remainingToSupplyToComp) * cEthExchangeRate) /
                1e18;
            lendingBalanceOf[msg.sender].onComp += remainingToSupplyToComp;
        } else {
            lendingBalanceOf[msg.sender].onComp += _amount; // In cToken.
        }
    }

    /** @dev Allows someone to borrow ETH.
     *  @param _amount The amount to borrow in ETH.
     */
    function borrow(uint256 _amount) external {
        // Calculate the collateral required.
        uint256 daiAmountEquivalentToEthAmount = (_amount * 1e18) /
            oracle.consult();
        uint256 collateralRequiredInDai = (daiAmountEquivalentToEthAmount *
            collateralFactor) / 1e18;
        // Calculate the collateral value of sender in DAI.
        uint256 collateralRequiredInCDai = (collateralRequiredInDai * 1e18) /
            cDaiToken.exchangeRateCurrent();
        // Check if sender has enough collateral.
        require(
            collateralRequiredInCDai <= collateralBalanceOf[msg.sender],
            "Not enough collateral."
        );
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountInCEth = (_amount * 1e18) / cEthExchangeRate;
        borrowingBalanceOf[msg.sender].total += _amount; // In underlying.
        uint256 remainingToBorrowOnComp = (_moveLendersFromCompToMorpho(
            amountInCEth,
            msg.sender
        ) * cEthExchangeRate) / 1e18; // In underlying.
        // If not enough cTokens on Morpho, we must borrow it on Compound.
        if (remainingToBorrowOnComp > 0) {
            cEthToken.borrow(remainingToBorrowOnComp); // Revert on error.
            borrowingBalanceOf[msg.sender].onComp += remainingToBorrowOnComp; // In underlying.
            borrowersOnComp.add(msg.sender);
            if (remainingToBorrowOnComp != _amount)
                borrowersOnMorpho.add(msg.sender);
        }
        _redeemEthFromComp(_amount - remainingToBorrowOnComp, false);
        // Transfer ETH to borrower.
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows a borrower to pay back its debt in ETH.
     *  @dev ETH is sent as msg.value.
     */
    function payBack() external payable {
        _payBack(msg.sender, msg.value);
    }

    /** @dev Allows a lender to cash-out in ETH.
     *  @param _amount The amount in ETH to cash-out.
     */
    function cashOut(uint256 _amount) external {
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountOnCompInEth = (lendingBalanceOf[msg.sender].onComp *
            cEthExchangeRate) / 1e18;
        if (_amount <= amountOnCompInEth) {
            lendingBalanceOf[msg.sender].onComp -=
                (_amount * 1e18) /
                cEthToken.exchangeRateCurrent(); // In cToken.
            _redeemEthFromComp(_amount, false);
        } else {
            lendingBalanceOf[msg.sender].onComp = 0;
            _redeemEthFromComp(amountOnCompInEth, false);
            uint256 remainingToCashOutInEth = _amount - amountOnCompInEth; // In underlying.
            lendingBalanceOf[msg.sender].onMorpho -= remainingToCashOutInEth; // In underlying.
            uint256 remainingToCashOutInCEth = (remainingToCashOutInEth *
                1e18) / cEthExchangeRate;
            uint256 cEthContractBalance = cEthToken.balanceOf(address(this));
            if (remainingToCashOutInCEth <= cEthContractBalance) {
                _moveLendersFromCompToMorpho(
                    remainingToCashOutInCEth,
                    msg.sender
                );
            } else {
                _moveLendersFromCompToMorpho(cEthContractBalance, msg.sender);
                remainingToCashOutInCEth -= cEthContractBalance;
                remainingToCashOutInCEth -=
                    (_moveBorrowersFromMorphoToComp(remainingToCashOutInCEth) *
                        1e18) /
                    cEthExchangeRate;
                cEthToken.borrow(
                    (remainingToCashOutInCEth * cEthExchangeRate) / 1e18
                ); // Revert on error.
            }
        }
        payable(msg.sender).transfer(_amount);
        // If lender has no lending at all, then remove her from `lenders`.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            lenders.remove(msg.sender);
        }
    }

    /** @dev Allows a lender to unstake its cETH.
     *  @param _amount Amount in cETH to unstake.
     */
    function unstake(uint256 _amount) external {
        if (_amount <= lendingBalanceOf[msg.sender].onComp) {
            lendingBalanceOf[msg.sender].onComp -= _amount;
        } else {
            uint256 cEthRateExchange = cEthToken.exchangeRateCurrent();
            uint256 remainingToUnstakeInCEth = _amount -
                lendingBalanceOf[msg.sender].onComp;
            lendingBalanceOf[msg.sender].onComp = 0;
            lendingBalanceOf[msg.sender].onMorpho -=
                (remainingToUnstakeInCEth * cEthRateExchange) /
                1e18;
            uint256 cEthContractBalance = cEthToken.balanceOf(address(this));
            if (remainingToUnstakeInCEth <= cEthContractBalance) {
                _moveLendersFromCompToMorpho(
                    remainingToUnstakeInCEth,
                    msg.sender
                );
            } else {
                _moveLendersFromCompToMorpho(cEthContractBalance, msg.sender);
                remainingToUnstakeInCEth -= cEthContractBalance;
                remainingToUnstakeInCEth -=
                    (_moveBorrowersFromMorphoToComp(remainingToUnstakeInCEth) *
                        1e18) /
                    cEthRateExchange;
                cEthToken.borrow(
                    (remainingToUnstakeInCEth * cEthRateExchange) / 1e18
                ); // Revert on error.
            }
        }
        cEthToken.transfer(msg.sender, _amount);
        // If lender has no lending at all, then remove her from `lenders`.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            lenders.remove(msg.sender);
        }
    }

    /** @dev Allows a borrower to provide collateral in DAI.
     *  @param _amount The amount in DAI to provide.
     */
    function provideCollateral(uint256 _amount) external {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.safeTransferFrom(msg.sender, address(this), _amount);
        _supplyDaiToComp(_amount);
        // Update the collateral balance of the sender in cDAI.
        collateralBalanceOf[msg.sender] +=
            (_amount * 1e18) /
            cDaiToken.exchangeRateCurrent();
    }

    /** @dev Allows a borrower to redeem her collateral in DAI.
     *  @param _amount The amount in DAI to get back.
     */
    function redeemCollateral(uint256 _amount) external {
        uint256 daiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 amountInCDai = (_amount * 1e18) / daiExchangeRate;
        require(
            amountInCDai <= collateralBalanceOf[msg.sender],
            "Must redeem less than collateral."
        );
        uint256 borrowingAmountInDai = (borrowingBalanceOf[msg.sender].total *
            1e18) / oracle.consult();
        uint256 collateralAfterInCDAI = collateralBalanceOf[msg.sender] -
            amountInCDai;
        uint256 collateralRequiredInCDai = (borrowingAmountInDai *
            collateralFactor) / daiExchangeRate;
        require(
            collateralAfterInCDAI >= collateralRequiredInCDai,
            "Health factor will drop below 1"
        );
        require(
            _redeemDaiFromComp(_amount, false) == 0,
            "Redeem cDAI on Compound failed."
        );
        collateralBalanceOf[msg.sender] -= amountInCDai; // In cToken.
        daiToken.safeTransfer(msg.sender, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _borrower The address of the borrower to liquidate.
     */
    function liquidate(address _borrower) external payable {
        (uint256 collateralInDai, uint256 collateralRequiredInDAI) = getAccountLiquidity(_borrower);
        require(
            collateralInDai < collateralRequiredInDAI,
            "Borrower position cannot be liquidated."
        );
        _payBack(_borrower, msg.value);
        // Calculation done step by step to avoid overflows.
        uint256 daiToEthRate = oracle.consult();
        uint256 borrowingAmountInDai = (borrowingBalanceOf[_borrower].total *
            1e18) / daiToEthRate;
        uint256 repayAmountInDai = (msg.value * 1e18) / daiToEthRate;
        uint256 daiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 daiAmountToTransfer = (repayAmountInDai * collateralInDai) /
            borrowingAmountInDai;
        uint256 cDaiAmountToTransfer = (daiAmountToTransfer * 1e18) /
            daiExchangeRate;
        cDaiAmountToTransfer = (cDaiAmountToTransfer * liquidationIncentive) / DENOMINATOR;
        require(
            collateralBalanceOf[_borrower] >= cDaiAmountToTransfer,
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceOf[_borrower] -= cDaiAmountToTransfer;
        _redeemDaiFromComp(daiAmountToTransfer, false);
        daiToken.safeTransfer(msg.sender, daiAmountToTransfer);
    }

    /** @dev Updates the collateral factor related to cETH.
     */
    function updateCollateralFactor() external {
        (, collateralFactor, ) = comptroller.markets(CETH_ADDRESS);
    }

    /* Public */

    /** @dev Returns the health factor of the `_borrower`.
     *  @dev When the health factor of a borrower fells below 1, she can be liquidated.
     *  @param _borrower The address of `_borrower`.
     *  @return collateralInDai The collateral of the `_borrower` in DAI.
     *  @return collateralRequiredInDai The collateral required of the `_borrower` in DAI.
     */
    function getAccountLiquidity(address _borrower)
        public
        returns (uint256 collateralInDai, uint256 collateralRequiredInDai)
    {
        collateralRequiredInDai = (borrowingBalanceOf[_borrower].total *
            collateralFactor) / oracle.consult();
        collateralInDai = (collateralBalanceOf[_borrower] *
            cDaiToken.exchangeRateCurrent()) / 1e18;
        return (collateralInDai, collateralInDai);
    }

    /* Internal */

    /** @dev Implements pay back logic.
     *  @param _borrower The address of the `_borrower` to pay back the borrowing.
     *  @param _amount The amount of ETH to pay back.
     */
    function _payBack(address _borrower, uint256 _amount) internal {
        if (borrowingBalanceOf[_borrower].onComp > 0) {
            if (_amount <= borrowingBalanceOf[_borrower].onComp) {
                // Repay Compound.
                borrowingBalanceOf[_borrower].onComp -= _amount;
                cEthToken.repayBorrow{value: _amount}(); // Revert on error.
                _supplyEthToComp(_amount);
            } else {
                // Repay Compound first.
                cEthToken.repayBorrow{value: borrowingBalanceOf[_borrower].onComp}(); // Revert on error.
                // Then, move remaining and supply it to Compound.
                uint256 remainingToSupplyToComp = _amount- borrowingBalanceOf[_borrower].onComp;
                uint256 remainingAmountToMoveInCEth = (remainingToSupplyToComp * 1e18) / cEthToken.exchangeRateCurrent(); // In cToken.
                borrowingBalanceOf[_borrower].onComp = 0;
                borrowersOnComp.remove(_borrower);
                _moveLendersFromMorphoToComp(remainingAmountToMoveInCEth, _borrower);
                _supplyEthToComp(remainingToSupplyToComp);
            }
        } else {
            _moveLendersFromMorphoToComp((_amount * 1e18) / cEthToken.exchangeRateCurrent(), _borrower);
            _supplyEthToComp(_amount);
        }
        borrowingBalanceOf[_borrower].total -= _amount;
        if (borrowingBalanceOf[_borrower].total == 0)
            borrowersOnMorpho.remove(_borrower);
    }

    /** @dev Supplies ETH to Compound.
     *  @param _amount The amount in ETH to supply.
     */
    function _supplyEthToComp(uint256 _amount) internal {
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    /** @dev Supplies DAI to Compound.
     *  @param _amount Amount in DAI to supply.
     */
    function _supplyDaiToComp(uint256 _amount) internal {
        // Approve transfer on the ERC20 contract.
        daiToken.safeApprove(CDAI_ADDRESS, _amount);
        // Mint cTokens.
        require(cDaiToken.mint(_amount) == 0, "cDAI minting failed.");
    }

    /** @dev Redeems DAI from Compound.
     *  @dev If `_redeemType` is true pass cDAI as argument, else pass DAI.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     *  @return result The result from Compound.
     */
    function _redeemDaiFromComp(uint256 _amount, bool _redeemType)
        internal
        returns (uint256 result)
    {
        if (_redeemType == true) {
            // Retrieve your asset based on a cDAI amount.
            result = cDaiToken.redeem(_amount);
        } else {
            // Retrieve your asset based on a DAI amount.
            result = cDaiToken.redeemUnderlying(_amount);
        }
    }

    /** @dev Redeems ETH from Compound.
     *  @dev If `_redeemType` is true pass cETH as argument, else pass ETH.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     *  @return result The result from Compound.
     */
    function _redeemEthFromComp(uint256 _amount, bool _redeemType)
        internal
        returns (uint256 result)
    {
        if (_redeemType == true) {
            // Retrieve your asset based on a cETH amount.
            result = cEthToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an ETH amount.
            result = cEthToken.redeemUnderlying(_amount);
        }
    }

    /** @dev Finds liquidity on Compound and moves it to Morpho.
     *  @param _amount The amount to search for in cETH.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     *  @return remainingToMove The remaining liquidity to search for in cETH.
     */
    function _moveLendersFromCompToMorpho(
        uint256 _amount,
        address _lenderToAvoid
    ) internal returns (uint256 remainingToMove) {
        remainingToMove = _amount; // In cToken.
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 onComp = lendingBalanceOf[lender].onComp;

                if (onComp > 0) {
                    uint256 amountToMove = min(onComp, remainingToMove); // In cToken.
                    lendingBalanceOf[lender].onComp -= amountToMove; // In cToken.
                    lendingBalanceOf[lender].onMorpho +=
                        (amountToMove * cEthExchangeRate) /
                        1e18; // In underlying.
                    remainingToMove -= amountToMove;
                }
            }
            i++;
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @param _amount The amount to search for in cETH.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     */
    function _moveLendersFromMorphoToComp(
        uint256 _amount,
        address _lenderToAvoid
    ) internal {
        uint256 remainingToMove = _amount; // In cToken.
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 used = lendingBalanceOf[lender].onMorpho;

                if (used > 0) {
                    uint256 amountToMove = min(used, remainingToMove); // In cToken.
                    lendingBalanceOf[lender].onComp += amountToMove; // In cToken.
                    lendingBalanceOf[lender].onMorpho -=
                        (amountToMove * cEthExchangeRate) /
                        1e18; // In underlying.
                    remainingToMove -= amountToMove; // In cToken.
                }
            }
            i++;
        }
        require(remainingToMove == 0, "Not enough liquidity to unuse.");
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @param _amount The amount to match in cETH.
     */
    function _moveBorrowersFromMorphoToComp(uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        remainingToMatch = _amount;
        uint256 i;
        while (remainingToMatch > 0 && i < borrowersOnMorpho.length()) {
            address borrower = borrowersOnMorpho.at(i);
            uint256 onMorpho = borrowingBalanceOf[borrower].total -
                borrowingBalanceOf[borrower].onComp;

            if (onMorpho > 0) {
                uint256 toMatch = min(onMorpho, remainingToMatch);
                remainingToMatch -= toMatch;
                borrowingBalanceOf[borrower].onComp += toMatch;
                borrowersOnComp.add(borrower);
            }
            i++;
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @param _amount The amount to match in ETH.
     *  @return remainingToMatch The amount remaining to match in ETH.
     */
    function _moveBorrowersFromCompToMorpho(uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        remainingToMatch = _amount;
        uint256 i;
        while (remainingToMatch > 0 && i < borrowersOnComp.length()) {
            address borrower = borrowersOnComp.at(i);

            if (borrowingBalanceOf[borrower].onComp > 0) {
                uint256 toMatch = min(
                    borrowingBalanceOf[borrower].onComp,
                    remainingToMatch
                );
                remainingToMatch -= toMatch;
                borrowingBalanceOf[borrower].onComp -= toMatch;
                if (borrowingBalanceOf[borrower].onComp == 0)
                    borrowersOnComp.remove(borrower);
            }
            i++;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    // This is needed to receive ETH when calling `redeemCEth`
    receive() external payable {}
}
