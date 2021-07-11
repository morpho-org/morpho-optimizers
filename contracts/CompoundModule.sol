pragma solidity >=0.6.6;

import "./libraries/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import {ICErc20, ICEth, IComptroller} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending.
 */
contract CompoundModule {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* Structs */

    struct LendingBalance {
        uint256 unused; // In cToken.
        uint256 used; // In underlying Token.
    }

    struct BorrowingBalance {
        uint256 balance; // In ETH.
        bool isWaiting; // Is the borrower on the waiting list.
    }

    /* Storage */

    mapping(address => LendingBalance) public lendingBalanceOf; // Lending balance of user (ETH/cETH).
    mapping(address => uint256) public borrowingBalanceOf; // Borrowing balance of user (ETH).
    mapping(address => uint256) public collateralBalanceOf; // Collateral balance of user (cDAI).
    mapping(address => uint256) public lenderToIndex; // Position of the lender in the currentLenders list.
    address[] public currentLenders; // Current lenders in the protocol.
    EnumerableSet.AddressSet private busyBorrowers; // Busy borrowers in the protocol.
    EnumerableSet.AddressSet private waitingBorrowers; // Waiting borrowers in the protocol.
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
        uint256 toSupply = msg.value;
        if (waitingBorrowers.length() > 0) {
            // Find borrowers in the waiting list and move them to the busy borrowers.
            _matchLendingWithWaitingBorrowers(msg.value);
            // Repay compound.
            uint256 morphoBorrowingBalance = cEthToken.borrowBalanceCurrent(address(this));
            uint256 toRepay = min(morphoBorrowingBalance, msg.value);
            if (morphoBorrowingBalance > msg.value) {
                toRepay = msg.value;
                toSupply = 0;
            } else {
                toRepay = morphoBorrowingBalance;
                toSupply = msg.value - morphoBorrowingBalance;
            }
            cEthToken.repayBorrow{value: toRepay}();
        }
        if (toSupply > 0) _supplyEthToCompound(toSupply);
        // If lender is not already in the list of lenders, add him to the list.
        if (lendingBalanceOf[msg.sender].unused == 0 && lendingBalanceOf[msg.sender].used == 0) {
            lenderToIndex[msg.sender] = currentLenders.length;
            currentLenders.push(msg.sender);
        }
        lendingBalanceOf[msg.sender].unused += msg.value.mul(1e18).div(
            cEthToken.exchangeRateCurrent()
        ); // In cToken.
    }

    /** @dev Allows someone to directly stake cETH.
     *  @param _amount Amount to stake in cETH.
     */
    function stake(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        cEthToken.transferFrom(msg.sender, address(this), _amount);
        // If lender is not already in the list of lenders, add him to the list.
        if (lendingBalanceOf[msg.sender].unused == 0 && lendingBalanceOf[msg.sender].used == 0) {
            lenderToIndex[msg.sender] = currentLenders.length;
            currentLenders.push(msg.sender);
        }
        lendingBalanceOf[msg.sender].unused += _amount; // In cToken.
    }

    /** @dev Allows someone to borrow ETH.)
     *  @param _amount Amount to borrow in ETH.
     */
    function borrow(uint256 _amount) external {
        // Calculate the collateral required.
        uint256 daiAmountEquivalentToEthAmount = _amount.mul(1e18).div(
            oracle.consult()
        );
        uint256 collateralRequiredInDai = daiAmountEquivalentToEthAmount
        .mul(collateralFactor)
        .div(1e18);
        // Calculate the collateral value of sender in DAI.
        uint256 collateralRequiredInCDai = collateralRequiredInDai
        .mul(1e18)
        .div(cDaiToken.exchangeRateCurrent());
        // Check if sender has enough collateral.
        require(
            collateralRequiredInCDai <= collateralBalanceOf[msg.sender],
            "Not enough collateral."
        );
        // Check if contract has the cTokens for the borrowing.
        uint256 amountInCEth = _amount.mul(1e18).div(
            cEthToken.exchangeRateCurrent()
        );
        require(
            amountInCEth <= cEthToken.balanceOf(address(this)),
            "Borrowing amount must be less than total available."
        );
        // If the borrower is not in the `busyBorrowers` list, add her to the list.
        if (!busyBorrowers.contains(msg.sender)) {
            require(busyBorrowers.add(msg.sender), "Borrower fails to be added");
        }
        // Now contract can take liquidity thanks to cTokens.
        _findUnusedCTokensAndUse(amountInCEth, msg.sender);
        borrowingBalanceOf[msg.sender] += _amount; // In underlying.
        _redeemEthFromCompound(_amount, false);
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
        uint256 unusedInEth = lendingBalanceOf[msg.sender]
        .unused
        .mul(cEthToken.exchangeRateCurrent())
        .div(1e18);
        if (_amount <= unusedInEth) {
            _cashOutUnused(msg.sender, _amount);
        } else {
            uint256 amountToCashOutInCEth = lendingBalanceOf[msg.sender]
            .unused - _amount.mul(1e18).div(cEthToken.exchangeRateCurrent()); // In cToken.
            _cashOutUnused(msg.sender, unusedInEth);
            uint256 amountToCashOutInEth = amountToCashOutInCEth
            .mul(cEthToken.exchangeRateCurrent())
            .div(1e18);
            if (cEthToken.balanceOf(address(this)) > amountToCashOutInCEth) {
                _findUnusedCTokensAndUse(amountToCashOutInCEth, msg.sender);
                lendingBalanceOf[msg.sender].used -= amountToCashOutInEth; // In underlying.
                payable(msg.sender).transfer(amountToCashOutInEth);
            } else {
                _findBusyBorrowers(_amount);
                cEthToken.borrow(_amount);
                payable(msg.sender).transfer(_amount);
            }
        }
        // If lender has no lending at all, then remove it from the list of lenders.
        if (
            lendingBalanceOf[msg.sender].unused == 0 &&
            lendingBalanceOf[msg.sender].used == 0
        ) {
            delete currentLenders[lenderToIndex[msg.sender]];
        }
    }

    /** @dev Allows a lender to unstake its cETH.
     *  @param _amount Amount in cETH to unstake.
     */
    function unstake(uint256 _amount) external {
        if (_amount <= lendingBalanceOf[msg.sender].unused) {
            _unstakeUnused(msg.sender, _amount);
        } else {
            _unstakeUnused(msg.sender, _amount);
            uint256 amountToUnstakeInCEth = lendingBalanceOf[msg.sender]
            .unused - _amount; // In cToken.
            if (cEthToken.balanceOf(address(this)) > amountToUnstakeInCEth) {
                _findUnusedCTokensAndUse(amountToUnstakeInCEth, msg.sender);
                lendingBalanceOf[msg.sender].used -= amountToUnstakeInCEth
                .mul(cEthToken.exchangeRateCurrent())
                .div(1e18); // In underlying.
                cEthToken.transfer(msg.sender, amountToUnstakeInCEth);
            } else {
                // TODO: find borrower to unused.
                revert("Not implemented yet.");
                cEthToken.borrow(_amount);
                payable(msg.sender).transfer(_amount);
            }
        }
        // If lender has no lending at all, then remove it from the list of lenders.
        if (
            lendingBalanceOf[msg.sender].unused == 0 &&
            lendingBalanceOf[msg.sender].used == 0
        ) {
            delete currentLenders[lenderToIndex[msg.sender]];
        }
    }

    /** @dev Allows a borrower to provide collateral in DAI.
     *  @param _amount Amount in DAI to provide.
     */
    function provideCollateral(uint256 _amount) external {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.transferFrom(msg.sender, address(this), _amount);
        _supplyDaiToCompound(_amount);
        // Update the collateral balance of the sender in cDAI.
        collateralBalanceOf[msg.sender] += _amount.mul(1e18).div(
            cDaiToken.exchangeRateCurrent()
        );
    }

    /** @dev Allows a borrower to redeem its collateral in DAI.
     *  @param _amount Amount in DAI to get back.
     */
    function redeemCollateral(uint256 _amount) external {
        uint256 daiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 amountInCDai = _amount.mul(1e18).div(daiExchangeRate);
        require(
            amountInCDai <= collateralBalanceOf[msg.sender],
            "Must redeem less than collateral."
        );
        uint256 borrowingAmount = borrowingBalanceOf[msg.sender].mul(1e18).div(
            oracle.consult()
        );
        uint256 borrowingAmountInDai = borrowingAmount;
        uint256 collateralAfterInCDAI = collateralBalanceOf[msg.sender].sub(
            amountInCDai
        );
        uint256 collateralRequiredInCDai = borrowingAmountInDai
        .mul(collateralFactor)
        .div(daiExchangeRate);
        require(
            collateralAfterInCDAI >= collateralRequiredInCDai,
            "Health factor will drop below 1"
        );
        require(
            _redeemDaiFromCompound(_amount, false) == 0,
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
        uint256 daiToEthRate = oracle.consult();
        uint256 borrowingAmountInDai = borrowingBalanceOf[_borrower]
        .mul(1e18)
        .div(daiToEthRate);
        uint256 repayAmountInDai = msg.value.mul(1e18).div(daiToEthRate);
        uint256 daiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 collateralInDai = collateralBalanceOf[_borrower]
        .mul(daiExchangeRate)
        .div(1e18);
        uint256 daiAmountToTransfer = repayAmountInDai.mul(collateralInDai).div(
            borrowingAmountInDai
        );
        uint256 cDaiAmountToTransfer = daiAmountToTransfer.mul(1e18).div(
            daiExchangeRate
        );
        require(
            collateralBalanceOf[_borrower] >= cDaiAmountToTransfer,
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceOf[_borrower] -= cDaiAmountToTransfer;
        _redeemDaiFromCompound(daiAmountToTransfer, false);
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
        uint256 borrowingAmountInDai = borrowingBalanceOf[_borrower]
        .mul(1e18)
        .div(oracle.consult());
        uint256 collateralRequiredInDai = borrowingAmountInDai
        .mul(collateralFactor)
        .div(1e18);
        uint256 collateralInDai = collateralBalanceOf[_borrower]
        .mul(cDaiToken.exchangeRateCurrent())
        .div(1e18);
        return collateralInDai.div(collateralRequiredInDai);
    }

    /* Internal */

    /** @dev Implements pay back logic.
     *  @param _borrower The address of the `_borrower`to pay back the borrowing.
     *  @param _amount The amount of ETH to pay back.
     */
    function _payBack(address _borrower, uint256 _amount) internal {
        uint256 amountInCEth = _amount.mul(1e18).div(
            cEthToken.exchangeRateCurrent()
        );
        borrowingBalanceOf[_borrower] -= _amount;
        // If `_borrower` has no more borrowing balance, remove her.
        if (borrowingBalanceOf[_borrower] == 0) {
            // No need to update `busyBorrowerToIndex` as it will be updated when `_borrower` will borrow another time.
            if (waitingBorrowers.contains(_borrower)) {
                waitingBorrowers.remove(_borrower);
                // TODO: like in lend
            } else {
                busyBorrowers.remove(_borrower);
            }
        }
        _findUsedCTokensAndUnuse(amountInCEth, _borrower);
        _supplyEthToCompound(_amount);
    }

    /** @dev Cashes-out `_lender`'s unused tokens.
     *  @param _lender Address of the lender to redeem lending for.
     *  @param _amount Amount in ETH to redeem.
     */
    function _cashOutUnused(address _lender, uint256 _amount) internal {
        uint256 amountInCEth = _amount.mul(1e18).div(
            cEthToken.exchangeRateCurrent()
        );
        require(
            amountInCEth <= lendingBalanceOf[_lender].unused,
            "Cannot redeem more than the lending amount provided."
        );
        // Update unused lending balance of `_lender`.
        lendingBalanceOf[_lender].unused -= amountInCEth; // In cToken.
        _redeemEthFromCompound(_amount, false);
        payable(_lender).transfer(_amount);
    }

    /** @dev Unstakes `_lender`'s unused tokens.
     *  @param _lender Address of the lender to redeem staked tokens for.
     *  @param _amount Amount in cETH to redeem.
     */
    function _unstakeUnused(address _lender, uint256 _amount) internal {
        require(
            _amount <= lendingBalanceOf[_lender].unused,
            "Cannot redeem more than the lending amount provided."
        );
        // Update unused lending balance of `_lender`.
        lendingBalanceOf[_lender].unused -= _amount; // In cToken.
        cEthToken.transfer(_lender, _amount);
    }

    /** @dev Supplies ETH to Compound.
     *  @param _amount Amount in ETH to supply.
     */
    function _supplyEthToCompound(uint256 _amount) internal {
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    /** @dev Supplies DAI to Compound.
     *  @param _amount Amount in DAI to supply.
     */
    function _supplyDaiToCompound(uint256 _amount) internal {
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
    function _redeemDaiFromCompound(uint256 _amount, bool _redeemType)
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
    function _redeemEthFromCompound(uint256 _amount, bool _redeemType)
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
     */
    function _findUnusedCTokensAndUse(uint256 _amount, address _lenderToAvoid)
        internal
    {
        uint256 remainingLiquidityToUse = _amount; // In cToken.
        uint256 i;
        while (remainingLiquidityToUse > 0 && i < currentLenders.length) {
            address lender = currentLenders[i];
            if (lender != _lenderToAvoid && lender != address(0)) {
                uint256 unused = lendingBalanceOf[lender].unused;

                if (unused > 0) {
                    uint256 amountToUse = min(unused, remainingLiquidityToUse); // In cToken.
                    lendingBalanceOf[lender].unused -= amountToUse; // In cToken.
                    lendingBalanceOf[lender].used += amountToUse
                    .mul(cEthToken.exchangeRateCurrent())
                    .div(1e18); // In underlying.
                    remainingLiquidityToUse -= amountToUse;
                }
            }
            i++;
        }
        require(remainingLiquidityToUse == 0, "Not enough liquidity to use.");
    }

    /** @dev Finds used cETH and unuses them.
     *  @param _amount Amount to use in cETH.
     *  @param _lenderToAvoid Address of the lender to avoid moving liquidity.
     */
    function _findUsedCTokensAndUnuse(uint256 _amount, address _lenderToAvoid)
        internal
    {
        uint256 remainingLiquidityToUnuse = _amount; // In cToken.
        uint256 i;
        while (remainingLiquidityToUnuse > 0 && i < currentLenders.length) {
            address lender = currentLenders[i];
            if (lender != _lenderToAvoid && lender != address(0)) {
                uint256 used = lendingBalanceOf[lender].used;

                if (used > 0) {
                    uint256 amountToUnuse = min(
                        used,
                        remainingLiquidityToUnuse
                    ); // In cToken.
                    lendingBalanceOf[lender].unused += amountToUnuse; // In cToken.
                    lendingBalanceOf[lender].used -= amountToUnuse
                    .mul(cEthToken.exchangeRateCurrent())
                    .div(1e18); // In underlying.
                    remainingLiquidityToUnuse -= amountToUnuse; // In cToken.
                }
            }
            i++;
        }
        require(
            remainingLiquidityToUnuse == 0,
            "Not enough liquidity to unuse."
        );
    }

    /** @dev Finds busy borrowers to move into the waiting list.
     *  @param _amount Amount to use in cETH.
     */
    function _findBusyBorrowers(uint256 _amount)
        internal
    {
        uint256 remainingLiquidityToSearch = _amount;
        uint256 i;
        while (remainingLiquidityToSearch > 0 && i < busyBorrowers.length()) {
            address borrower = busyBorrowers.at(i);
            uint256 borrowingBalance = borrowingBalanceOf[borrower];

            if (borrowingBalance > 0) {
                uint256 amountAvailable = min(
                    borrowingBalance,
                    remainingLiquidityToSearch
                );
                remainingLiquidityToSearch -= amountAvailable;
                busyBorrowers.remove(borrower);
                waitingBorrowers.add(borrower);
            }
            i++;
        }
        require(
            remainingLiquidityToSearch == 0,
            "Not enough liquidity to unuse."
        );
    }

    function _matchLendingWithWaitingBorrowers(uint256 _amount) internal returns(uint256) {
        uint256 remainingLiquidityToSearch = _amount;
        uint256 i;
        while (remainingLiquidityToSearch > 0 && i < waitingBorrowers.length()) {
            address borrower = waitingBorrowers.at(i);
            uint256 borrowingBalance = borrowingBalanceOf[borrower];

            if (borrowingBalance > 0) {
                uint256 amountAvailable = min(
                    borrowingBalance,
                    remainingLiquidityToSearch
                );
                remainingLiquidityToSearch -= amountAvailable;
                waitingBorrowers.remove(borrower);
                waitingBorrowers.add(borrower);
            }
            i++;
        }
        return remainingLiquidityToSearch;
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
