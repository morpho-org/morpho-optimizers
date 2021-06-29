pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SlidingWindowOracle.sol";

import {ICErc20, ICEth} from "./interfaces/ICompound.sol";

contract CompoundModule is SlidingWindowOracle, Math {
    /* Structs */

    struct Balance {
        uint256 total;
        uint256 used;
    }

    /* Storage */

    mapping(address => Balance) lendingBalanceOf;
    mapping(address => Balance) collateralBalanceOf;
    mapping(address => uint256) borrowingBalanceOf;
    mapping(address => uint256) lenderToIndex; // return the position of the lender in the currentLenders list
    address[] currentLenders;
    uint256 constant COLLATERAL_FACTOR = 12000; // Collateral factor in basis points 120% by default.
    uint256 constant DENOMINATOR = 10000; // Collateral factor in basis points.

    address constant wethAddress = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
    address payable constant cEtherAddress =
        payable(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address constant daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address payable constant cDaiAddress =
        payable(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

    ICEth public cEthToken = ICEth(cEtherAddress);
    ICErc20 public cDaiToken = ICErc20(cDaiAddress);
    IERC20 public daiToken = IERC20(daiAddress);

    /* External */

    function lend() external payable {

        _supplyEthToCompound{value: msg.value}();
        if (lendingBalanceOf[msg.sender].total == 0) {
            lenderToIndex[msg.sender] = currentLenders.length;
            currentLenders.push(msg.sender);
        }
        lendingBalanceOf[msg.sender].total += msg.value;
    }

    function borrow(uint256 _amount) external {
        // Verify that borrower has enough collateral
        uint256 daiAmountOut = consult(WETHAddress, _amount, daiAddress);
        uint256 unusedCollateral = collateralBalanceOf[msg.sender].total -
            collateralBalanceOf[msg.sender].used;
        uint256 collateralNeeded = (daiAmountOut / DENOMINATOR) *
            COLLATERAL_FACTOR;
        require(collateralNeeded <= unusedCollateral, "Not enough collateral.");

        // Check if contract has the cTokens for the borrowing
        // TODO: Verify multiplication, rounds
        uint256 availableTokensToBorrow = cDaiToken.balanceOf(address(this)) *
            cDaiToken.exchangeRateCurrent();
        require(_amount <= availableTokensToBorrow, "");

        // Now contract can take liquidity thanks to cTokens
        _findUnusedCTokensAndUse(_amount);

        // Update used collateral
        collateralBalanceOf[msg.sender].used += collateralNeeded;
        borrowingBalanceOf[msg.sender] += _amount;

        // Transfer ETH to borrower
        msg.sender.transfer(_amount);
    }

    function payBackAll() external payable {
        require(
            msg.value >= borrowingBalanceOf[msg.sender],
            "Must payback all debt."
        );
        address(this).transfer(msg.value);
        _supplyEthToCompound{value: msg.value}();
        _findUsedCTokensAndUnuse(msg.value);
        uint256 daiAmountOut = consult(wethAddress, msg.value, daiAddress); // This is the equivalent amount to repay  in DAI
        uint256 amountToRedeem = (daiAmountOut / DENOMINATOR) *
            COLLATERAL_FACTOR;
        borrowingBalanceOf[msg.sender] = 0;
        _redeemCollateral(_borrower, amountToRedeem);
    }

    function cashOut(uint256 _amount) external {
        _cashOut(msg.sender, _amount);
    }

    function provideCollateral(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        IERC20(daiToken).approve(address(this), _amount);
        IERC20(daiToken).transferFrom(msg.sender, address(this), msg.value);
        _supplyDaiToCompound(_amount);
        // We update the collateral balance of the message sender
        collateralBalanceOf[msg.sender].total += _amount;
    }

    // function redeemAllCollateral() external {
    //     uint amountToRedeem = collateralBalanceOf[msg.sender].total;
    //     _redeemCollateral(msg.sender, amountToRedeem);
    // }

    function liquidate(address _borrower) external {
        // TODO: write function
    }

    /* Internal */

    function _cashOut(address _lender, uint256 _amount) internal {
        if (lendingBalanceOf[_lender].used == 0) {
            lendingBalanceOf[_lender].total -= _amount;
            _redeemLending(_amount);
        } else if (cEthToken.balanceOf(address(this)) > 0) {
            _findUnusedCTokensAndUse(_amount);
            _redeemLending(_amount);
        } else {
            cEthToken.borrow(_amount);
            borrowingBalanceOf[_lender] += _amount;
            lendingBalanceOf[_lender].total -= _amount;
            require(_lender.send(_amount));
        }
        delete currentLenders[lenderToIndex[_lender]];
    }

    function _redeemCollateral(address _borrower, uint256 _amount) internal {
        require(
            isNotBorrowing(_borrower),
            "Borrowing must be repaid before redeeming collateral."
        );
        require(_amount <= collateralBalanceOf[msg.sender].total);
        _redeemCDaiFromCompound(_amount, false);
        // Amount of Tokens given by Compound calculation
        uint256 amountRedeemed = _amount * cDaiToken.exchangeRateCurrent();
        collateralBalanceOf[msg.sender].total -= _amount;
        // Finally leech transfers it to the user
        daiToken.transferFrom(address(this), _borrower, amountRedeemed);
    }

    function _redeemLending(address _lender, uint256 _amount) internal {
        require(_amount <= lendingBalanceOf[msg.sender].total);
        _redeemCEthFromCompoundTokens(_amount, false);
        // Amount of Tokens given by Compound calculation
        uint256 amountRedeemed = _amount * cEthToken.exchangeRateCurrent();
        // The sender does not have any collateral anymore
        lendingBalanceOf[msg.sender].total -= _amount;
        // Finally leech transfers it to the user
        _lender.transfer(amountRedeemed);
    }

    function _supplyEthToCompound() internal payable returns (bool) {
        uint256 result = cEthToken.mint{value: msg.value}();
        require(result == 0, "");
    }

    function _supplyDaiToCompound(uint256 _amount) internal {
        // Approve transfer on the ERC20 contract.
        underlying.approve(cDaiAddress, _amount);
        // Mint cTokens.
        require(cDaiToken.mint(_amount) == 0, "");
    }

    function _redeemCDaiFromCompound(uint256 _amount, bool _redeemType)
        internal
    {
        uint256 result;
        // TODO: check here this is false
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cDaiToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cDaiToken.redeemUnderlying(_amount);
        }
        require(result == 0, "");
    }

    function _redeemCEthFromCompound(uint256 _amount, bool _redeemType)
        internal
        returns (bool)
    {
        uint256 result;
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cEthToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cEthToken.redeemUnderlying(_amount);
        }
        require(result == 0, "");
    }

    // TODO: can be a public function
    function _calculateAmountToRepay(address _borrower)
        internal
        returns (uint256)
    {
        return borrowingBalanceOf[_borrower].used;
    }

    // TODO: can be a modifier or removed it as it's used only once
    function isNotBorrowing(address _borrower) internal returns (bool) {
        return (borrowingBalanceOf[_borrower].used == 0);
    }

    function _findUnusedCTokensAndUse(uint256 _amount) internal {
        uint256 remainingLiquidityToUse = _amount;
        uint256 i;
        while (remainingLiquidityToUse > 0 && i < currentLenders.length) {
            address lenderAddress = currentLenders[i];
            // We calculate how much is unused=usable for this lender
            uint256 usable = lendingBalanceOf[lenderAddress].total -
                lendingBalanceOf[lenderAddress].used;

            if (usable > 0) {
                uint256 amountToUse = min(usable, remainingLiquidityToUse);
                lendingBalanceOf[lenderAddress].used += amountToUse;
                remainingLiquidityToUse -= amountToUse;
            }
            i += 1;
        }
        require(remainingLiquidityToUse == 0);
    }

    function _findUsedCTokensAndUnuse(uint256 _amount) internal {
        uint256 remainingLiquidityToUnuse = _amount;
        uint256 i = currentLenders.length;
        while (remainingLiquidityToUnuse > 0 && i < currentLenders.length) {
            address lenderAddress = currentLenders[i];
            // We calculate how much is used=unusable for this lender
            uint256 unusable = lendingBalanceOf[lenderAddress].used;

            if (unusable > 0) {
                uint256 amountToUnuse = min(
                    unusable,
                    remainingLiquidityToUnuse
                );
                lendingBalanceOf[lenderAddress].used -= amountToUnuse;
                remainingLiquidityToUnuse -= amountToUnuse;
            }
            i += 1;
        }
        require(remainingLiquidityToUnuse == 0);
    }
}
