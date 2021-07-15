pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import {ICErc20, ICEth, IComptroller} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending.
 */
contract CompoundModule {
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
    EnumerableSet.AddressSet private lenders; // Current lenders in the protocol.
    EnumerableSet.AddressSet private borrowersOnMorpho; // Busy borrowers in the protocol.
    EnumerableSet.AddressSet private borrowersOnComp; // Waiting borrowers in the protocol.
    uint256 public collateralFactor = 1e18; // Collateral Factor related to cETH.

    address public constant COMPTROLLER_ADDRESS =
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

    IComptroller public comptroller = IComptroller(COMPTROLLER_ADDRESS);
    ICEth public cEthToken = ICEth(CETH_ADDRESS);
    ICErc20 public cDaiToken = ICErc20(CDAI_ADDRESS);
    IERC20 public daiToken = IERC20(DAI_ADDRESS);
    IOracle public oracle = IOracle(ORACLE_ADDRESS);

    /* External */

    /** @dev Allows someone to lend ETH.
     *  @dev ETH is sent through msg.value.
     */
    function lend() external payable {
        require(msg.value > 0, "Amount cannot be 0");
        // If lender is not already in the list of lenders, add him to the list.
        if (!lenders.contains(msg.sender))
            require(lenders.add(msg.sender), "Fails to add lender to lenders");
        uint256 toSupplyToCompound = msg.value;
        uint256 cEthExchangerate = cEthToken.exchangeRateCurrent();
        // If there are waiting borrowers we must empty this list first.
        if (borrowersOnComp.length() > 0) {
            // Find borrowers in the waiting list and move them to the borrowersOnMorpho.
            uint256 unused = (_moveBorrowersFromCompToMorpho(msg.value) *
                1e18) / cEthExchangerate;
            uint256 morphoBorrowingBalance = cEthToken.borrowBalanceCurrent(
                address(this)
            ); // In underlying.
            // Repay Compound if needed.
            if (morphoBorrowingBalance > 0) {
                if (morphoBorrowingBalance > msg.value) {
                    toSupplyToCompound = 0;
                    cEthToken.repayBorrow{value: msg.value}(); // Revert on error.
                } else {
                    toSupplyToCompound = msg.value - morphoBorrowingBalance;
                    cEthToken.repayBorrow{value: morphoBorrowingBalance}(); // Revert on error.
                }
            }
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                msg.value -
                ((unused * cEthExchangerate) / 1e18); // In underlying.
            lendingBalanceOf[msg.sender].onComp += unused; // In cToken.
        } else {
            lendingBalanceOf[msg.sender].onComp +=
                (msg.value * 1e18) /
                cEthExchangerate; // In cToken.
        }
        if (toSupplyToCompound > 0) _supplyEthToComp(toSupplyToCompound);
    }

    /** @dev Allows someone to directly stake cETH.
     *  @param _amount Amount to stake in cETH.
     */
    function stake(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        // If lender is not already in the list of lenders, add him to the list.
        if (!lenders.contains(msg.sender))
            require(lenders.add(msg.sender), "Fails to add lender to lenders.");
        cEthToken.transferFrom(msg.sender, address(this), _amount);
        // If there are waiting borrowers we must empty this list first.
        if (borrowersOnComp.length() > 0) {
            uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
            uint256 amountInEth = (_amount * cEthExchangeRate) / 1e18;
            // Find borrowers in the waiting list and move them to the borrowersOnMorpho.
            uint256 unused = (_moveBorrowersFromCompToMorpho(amountInEth) *
                1e18) / cEthExchangeRate;
            uint256 morphoBorrowingBalance = cEthToken.borrowBalanceCurrent(
                address(this)
            ); // In underlying.
            // Repay Compound if needed.
            if (morphoBorrowingBalance > 0) {
                uint256 amountToRepay = min(
                    morphoBorrowingBalance,
                    amountInEth
                );
                _redeemEthFromComp(amountToRepay, false);
                cEthToken.repayBorrow{value: amountToRepay}(); // Revert on error.
            }
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                ((_amount - unused) * cEthExchangeRate) /
                1e18;
            lendingBalanceOf[msg.sender].onComp += unused;
        } else {
            lendingBalanceOf[msg.sender].onComp += _amount; // In cToken.
        }
    }

    /** @dev Allows someone to borrow ETH.
     *  @param _amount Amount to borrow in ETH.
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
        // Check if contract has the cTokens for the borrowing.
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountInCEth = (_amount * 1e18) / cEthExchangeRate;
        // TODO: remove this requirement as the borrower can be in a waiting state?
        require(
            amountInCEth <= cEthToken.balanceOf(address(this)),
            "Borrowing amount must be less than total available."
        );
        // Now contract can take liquidity thanks to cTokens.
        borrowingBalanceOf[msg.sender].total += _amount; // In underlying.
        uint256 waiting = (_moveLendersFromCompToMorpho(
            amountInCEth,
            msg.sender
        ) * cEthExchangeRate) / 1e18; // In underlying.
        if (waiting > 0) {
            borrowingBalanceOf[msg.sender].onComp += waiting; // In underlying.
            borrowersOnComp.add(msg.sender);
            if (waiting != _amount) borrowersOnMorpho.add(msg.sender);
        }
        _redeemEthFromComp(_amount, false);
        // Transfer ETH to borrower
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows a borrower to pay back its debt in ETH.
     *  @dev ETH is sent as msg.value.
     */
    function payBack() external payable {
        _payBack(msg.sender, msg.value);
    }

    /** @dev Allows a lender to cash-out in ETH.
     *  @param _amount Amount in ETH to cash-out.
     */
    function cashOut(uint256 _amount) external {
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 unusedInEth = (lendingBalanceOf[msg.sender].onComp *
            cEthExchangeRate) / 1e18;
        if (_amount <= unusedInEth) {
            lendingBalanceOf[msg.sender].onComp -=
                (_amount * 1e18) /
                cEthToken.exchangeRateCurrent(); // In cToken.
            _redeemEthFromComp(_amount, false);
        } else {
            lendingBalanceOf[msg.sender].onComp = 0;
            _redeemEthFromComp(unusedInEth, false);
            uint256 amountToCashOutInEth = _amount - unusedInEth;
            lendingBalanceOf[msg.sender].onMorpho -= amountToCashOutInEth;
            uint256 amountToCashOutInCEth = (amountToCashOutInEth * 1e18) /
                cEthExchangeRate;
            uint256 cEthContractBalance = cEthToken.balanceOf(address(this));
            if (amountToCashOutInCEth <= cEthContractBalance) {
                // TODO: add require _moveLendersFromCompToMorpho == 0 ?
                _moveLendersFromCompToMorpho(amountToCashOutInCEth, msg.sender);
            } else {
                _moveLendersFromCompToMorpho(cEthContractBalance, msg.sender);
                amountToCashOutInCEth -= cEthContractBalance;
                amountToCashOutInCEth -=
                    (_moveBorrowersFromMorphoToComp(amountToCashOutInCEth) *
                        1e18) /
                    cEthToken.exchangeRateCurrent();
                cEthToken.borrow(amountToCashOutInCEth); // Revert on error.
            }
        }
        payable(msg.sender).transfer(_amount);
        // If lender has no lending at all, then remove it from the list of lenders.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            require(
                lenders.remove(msg.sender),
                "Fails to remove lender from lenders."
            );
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
            uint256 amountToUnstakeInCEth = _amount -
                lendingBalanceOf[msg.sender].onComp;
            lendingBalanceOf[msg.sender].onComp = 0;
            lendingBalanceOf[msg.sender].onMorpho -=
                (amountToUnstakeInCEth * cEthRateExchange) /
                1e18;
            uint256 cEthContractBalance = cEthToken.balanceOf(address(this));
            if (amountToUnstakeInCEth <= cEthContractBalance) {
                // TODO: add require _moveLendersFromCompToMorpho == 0 ?
                _moveLendersFromCompToMorpho(amountToUnstakeInCEth, msg.sender);
            } else {
                _moveLendersFromCompToMorpho(cEthContractBalance, msg.sender);
                amountToUnstakeInCEth -= cEthContractBalance;
                amountToUnstakeInCEth -=
                    (_moveBorrowersFromMorphoToComp(amountToUnstakeInCEth) *
                        1e18) /
                    cEthToken.exchangeRateCurrent();
                cEthToken.borrow(amountToUnstakeInCEth); // Revert on error.
            }
        }
        cEthToken.transfer(msg.sender, _amount);
        // If lender has no lending at all, then remove it from the list of lenders.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            require(
                lenders.remove(msg.sender),
                "Fails to remove lender from lenders."
            );
        }
    }

    /** @dev Allows a borrower to provide collateral in DAI.
     *  @param _amount Amount in DAI to provide.
     */
    function provideCollateral(uint256 _amount) external {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.transferFrom(msg.sender, address(this), _amount);
        _supplyDaiToComp(_amount);
        // Update the collateral balance of the sender in cDAI.
        collateralBalanceOf[msg.sender] +=
            (_amount * 1e18) /
            cDaiToken.exchangeRateCurrent();
    }

    /** @dev Allows a borrower to redeem its collateral in DAI.
     *  @param _amount Amount in DAI to get back.
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
        daiToken.transfer(msg.sender, _amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _borrower The address of the borrowe to liquidate.
     */
    function liquidate(address _borrower) external payable {
        require(
            getAccountHealthFactor(_borrower) < 1,
            "Borrower position cannot be liquidated."
        );
        _payBack(_borrower, msg.value);
        // Calculation done step by step to avoid overflows.
        uint256 daiToEthRate = oracle.consult();
        uint256 borrowingAmountInDai = (borrowingBalanceOf[_borrower].total *
            1e18) / daiToEthRate;
        uint256 repayAmountInDai = (msg.value * 1e18) / daiToEthRate;
        uint256 daiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 collateralInDai = (collateralBalanceOf[_borrower] *
            daiExchangeRate) / 1e18;
        uint256 daiAmountToTransfer = (repayAmountInDai * collateralInDai) /
            borrowingAmountInDai;
        uint256 cDaiAmountToTransfer = (daiAmountToTransfer * 1e18) /
            daiExchangeRate;
        require(
            collateralBalanceOf[_borrower] >= cDaiAmountToTransfer,
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceOf[_borrower] -= cDaiAmountToTransfer;
        _redeemDaiFromComp(daiAmountToTransfer, false);
        daiToken.transfer(msg.sender, daiAmountToTransfer);
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
     *  @return The health factor.
     */
    function getAccountHealthFactor(address _borrower)
        public
        returns (uint256)
    {
        uint256 collateralRequiredInDai = (borrowingBalanceOf[_borrower].total *
            collateralFactor) / oracle.consult();
        uint256 collateralInDai = (collateralBalanceOf[_borrower] *
            cDaiToken.exchangeRateCurrent()) / 1e18;
        return collateralInDai / collateralRequiredInDai;
    }

    /* Internal */

    /** @dev Implements pay back logic.
     *  @param _borrower The address of the `_borrower` to pay back the borrowing.
     *  @param _amount The amount of ETH to pay back.
     */
    function _payBack(address _borrower, uint256 _amount) internal {
        uint256 amountInCEth = (_amount * 1e18) /
            cEthToken.exchangeRateCurrent();
        borrowingBalanceOf[_borrower].total -= _amount;
        // If `_borrower` has no more borrowing balance, remove her.
        if (borrowingBalanceOf[_borrower].total == 0) {
            borrowersOnComp.remove(_borrower);
            borrowersOnMorpho.remove(_borrower);
        }
        // NOTE: what do we do if not enough Used cTokens? Can it happen?
        _moveLendersFromMorphoToComp(amountInCEth, _borrower);
        _supplyEthToComp(_amount);
    }

    /** @dev Supplies ETH to Compound.
     *  @param _amount Amount in ETH to supply.
     */
    function _supplyEthToComp(uint256 _amount) internal {
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    /** @dev Supplies DAI to Compound.
     *  @param _amount Amount in DAI to supply.
     */
    function _supplyDaiToComp(uint256 _amount) internal {
        // Approve transfer on the ERC20 contract.
        daiToken.approve(CDAI_ADDRESS, _amount);
        // Mint cTokens.
        require(cDaiToken.mint(_amount) == 0, "cDAI minting failed.");
    }

    /** @dev Redeems DAI from Compound.
     *  @dev If `_redeemType` is true pass cDAI as argument, else pass DAI.
     *  @param _amount Amount of tokens to be redeemed.
     *  @param _redeemType The redeem type to use on Compound.
     *  @return result Result from Compound.
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
     *  @return result Result from Compound.
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

    /** @dev Finds unused cETH and uses them.
     *  @param _amount Amount to unuse in cETH.
     *  @param _lenderToAvoid Address of the lender to avoid moving liquidity.
     *  @return remainingLiquidityToUse The remaining liquidity to use in cETH.
     */
    function _moveLendersFromCompToMorpho(
        uint256 _amount,
        address _lenderToAvoid
    ) internal returns (uint256 remainingLiquidityToUse) {
        remainingLiquidityToUse = _amount; // In cToken.
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 i;
        while (remainingLiquidityToUse > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 unused = lendingBalanceOf[lender].onComp;

                if (unused > 0) {
                    uint256 amountToUse = min(unused, remainingLiquidityToUse); // In cToken.
                    lendingBalanceOf[lender].onComp -= amountToUse; // In cToken.
                    lendingBalanceOf[lender].onMorpho +=
                        (amountToUse * cEthExchangeRate) /
                        1e18; // In underlying.
                    remainingLiquidityToUse -= amountToUse;
                }
            }
            i++;
        }
    }

    /** @dev Finds used cETH and unuses them.
     *  @param _amount Amount to use in cETH.
     *  @param _lenderToAvoid Address of the lender to avoid moving liquidity.
     */
    function _moveLendersFromMorphoToComp(
        uint256 _amount,
        address _lenderToAvoid
    ) internal {
        uint256 remainingLiquidityToUnuse = _amount; // In cToken.
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 i;
        while (remainingLiquidityToUnuse > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 used = lendingBalanceOf[lender].onMorpho;

                if (used > 0) {
                    uint256 amountToUnuse = min(
                        used,
                        remainingLiquidityToUnuse
                    ); // In cToken.
                    lendingBalanceOf[lender].onComp += amountToUnuse; // In cToken.
                    lendingBalanceOf[lender].onMorpho -=
                        (amountToUnuse * cEthExchangeRate) /
                        1e18; // In underlying.
                    remainingLiquidityToUnuse -= amountToUnuse; // In cToken.
                }
            }
            i++;
        }
        // TODO: check the consequences of this require.
        require(
            remainingLiquidityToUnuse == 0,
            "Not enough liquidity to unuse."
        );
    }

    /** @dev Finds busy borrowers to match the given `_amount` of ETH.
     *  @param _amount Amount to use in cETH.
     */
    function _moveBorrowersFromMorphoToComp(uint256 _amount)
        internal
        returns (uint256 remainingLiquidityToSearch)
    {
        remainingLiquidityToSearch = _amount;
        uint256 i;
        while (
            remainingLiquidityToSearch > 0 && i < borrowersOnMorpho.length()
        ) {
            address borrower = borrowersOnMorpho.at(i);
            uint256 busyBalance = borrowingBalanceOf[borrower].total -
                borrowingBalanceOf[borrower].onComp;

            if (busyBalance > 0) {
                uint256 amountAvailable = min(
                    busyBalance,
                    remainingLiquidityToSearch
                );
                remainingLiquidityToSearch -= amountAvailable;
                borrowingBalanceOf[borrower].onComp += amountAvailable;
                borrowersOnComp.add(borrower);
            }
            i++;
        }
    }

    /** @dev Matches a certain amount of ETH with borrowings in the waiting list.
     *  @param _amount Amount to use in ETH.
     *  @return remainingLiquidityToMatch The amount remaining in ETH after matching.
     */
    function _moveBorrowersFromCompToMorpho(uint256 _amount)
        internal
        returns (uint256 remainingLiquidityToMatch)
    {
        remainingLiquidityToMatch = _amount;
        uint256 i;
        while (remainingLiquidityToMatch > 0 && i < borrowersOnComp.length()) {
            address borrower = borrowersOnComp.at(i);

            if (borrowingBalanceOf[borrower].onComp > 0) {
                uint256 amountAvailable = min(
                    borrowingBalanceOf[borrower].onComp,
                    remainingLiquidityToMatch
                );
                remainingLiquidityToMatch -= amountAvailable;
                borrowingBalanceOf[borrower].onComp -= amountAvailable;
                if (borrowingBalanceOf[borrower].onComp == 0) {
                    require(
                        borrowersOnComp.remove(borrower),
                        "Fails to add borrower to borrowersOnComp."
                    );
                }
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
