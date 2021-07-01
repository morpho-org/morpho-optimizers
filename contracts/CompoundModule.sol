pragma solidity >=0.6.6;

import "./libraries/SafeMath.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import {ICErc20, ICEth} from "./interfaces/ICompound.sol";


contract CompoundModule {
    using SafeMath for uint256;

    event MyLog(string, uint256);

    /* Structs */

    struct Balance {
        uint256 unused; // In cToken.
        uint256 used; // In underlying Token.
    }

    /* Storage */

    mapping(address => Balance) public lendingBalanceOf; // Lending balance of user (ETH/cETH).
    mapping(address => Balance) public collateralBalanceOf; // Collateral balance of user (ETH/cETH).
    mapping(address => uint256) public borrowingBalanceOf; // Borrowing balance of user (cDAI).
    mapping(address => uint256) public lenderToIndex; // Position of the lender in the currentLenders list.
    address[] public currentLenders; // Current lenders in the protocol.
    uint256 public constant COLLATERAL_FACTOR = 10000; // Collateral factor in basis points 100% by default.
    uint256 public constant DENOMINATOR = 10000; // Collateral factor in basis points.

    address public constant WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address payable public constant CETH_ADDRESS =
        payable(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI_ADDRESS =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address payable public constant CDAI_ADDRESS =
        payable(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant ORACLE_ADDRESS =
        0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    ICEth public cEthToken = ICEth(CETH_ADDRESS);
    ICErc20 public cDaiToken = ICErc20(CDAI_ADDRESS);
    IERC20 public daiToken = IERC20(DAI_ADDRESS);
    IOracle public oracle = IOracle(ORACLE_ADDRESS);

    /* External */

    function lend() external payable {
        _supplyEthToCompound(msg.value);
        if (lendingBalanceOf[msg.sender].unused == 0) {
            lenderToIndex[msg.sender] = currentLenders.length;
            currentLenders.push(msg.sender);
        }
        uint exchangeRate = cEthToken.exchangeRateCurrent();
        lendingBalanceOf[msg.sender].unused += msg.value * exchangeRate;
    }

    function borrow(uint256 _amount) external {
        // Calculate the collateral needed.
        uint256 daiAmountEquivalentToEthAmount = oracle.consult(
            WETH_ADDRESS,
            _amount,
            DAI_ADDRESS
        );
        uint collateralNeeded = (daiAmountEquivalentToEthAmount /
            DENOMINATOR) * COLLATERAL_FACTOR;
        // Calculate the collateral value of sender in DAI.
        uint collateralValueInDAI = collateralBalanceOf[msg.sender].unused / cDaiToken.exchangeRateCurrent();
        require(collateralNeeded <= collateralValueInDAI, "Not enough collateral.");

        // Check if contract has the cTokens for the borrowing.
        uint256 availableTokensToBorrowInDAI = cDaiToken.balanceOf(address(this)) / cDaiToken.exchangeRateCurrent();
        require(
            _amount <= availableTokensToBorrowInDAI,
            "Amount to borrow should be less than total available."
        );

        // Now contract can take liquidity thanks to cTokens.
        _findUnusedCTokensAndUse(_amount);

        // Update used and unused collateral.
        collateralBalanceOf[msg.sender].unused -= _amount * cDaiToken.exchangeRateCurrent();
        collateralBalanceOf[msg.sender].used += collateralNeeded;
        borrowingBalanceOf[msg.sender] += _amount;

        // Transfer ETH to borrower
        payable(msg.sender).transfer(_amount);
    }

    function payBackAll() external payable {
        require(
            msg.value >= borrowingBalanceOf[msg.sender],
            "Must payback all the debt."
        );
        payable(address(this)).transfer(msg.value);
        _supplyEthToCompound(msg.value);
        _findUsedCTokensAndUnuse(msg.value);
        uint256 daiAmountEquivalentToEthAmount = oracle.consult(
            WETH_ADDRESS,
            msg.value,
            DAI_ADDRESS
        );
        uint256 amountToRedeem = (daiAmountEquivalentToEthAmount /
            DENOMINATOR) * COLLATERAL_FACTOR;
        borrowingBalanceOf[msg.sender] = 0;
        _redeemCollateral(msg.sender, amountToRedeem);
    }

    function cashOut(uint256 _amount) external {
        emit MyLog("value", _amount);
        _cashOut(msg.sender, _amount);
    }

    function provideCollateral(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.approve(address(this), _amount);
        daiToken.transferFrom(msg.sender, address(this), msg.value);
        _supplyDaiToCompound(_amount);
        // We update the collateral balance of the sender.
        collateralBalanceOf[msg.sender].total += _amount;
    }

    function redeemCollateral(uint256 _amount) external {
        _redeemCollateral(msg.sender, _amount);
    }

    function liquidate(address _borrower) external {
        // TODO: write function
    }

    /* Internal */

    function _cashOut(address _lender, uint256 _amount) internal {
        if (lendingBalanceOf[_lender].used == 0) {
            _redeemLending(_lender, _amount);
        } else if (cEthToken.balanceOf(address(this)) > 0) {
            _findUnusedCTokensAndUse(_amount);
            _redeemLending(_lender, _amount);
        } else {
            cEthToken.borrow(_amount);
            borrowingBalanceOf[_lender] += _amount;
            payable(_lender).transfer(_amount);
        }
        delete currentLenders[lenderToIndex[_lender]];
    }

    function _redeemCollateral(address _borrower, uint256 _amount) internal {
        require(
            borrowingBalanceOf[_borrower] == 0,
            "Borrowing must be repaid before redeeming collateral."
        );
        require(_amount <= collateralBalanceOf[msg.sender].total, "");
        require(_redeemCDaiFromCompound(_amount, false) == 0, "");
        collateralBalanceOf[msg.sender].total -= _amount;
        daiToken.transferFrom(address(this), _borrower, _amount);
    }

    function _redeemLending(address _lender, uint256 _amount) internal { //amount in eth
        require(
            _amount <= lendingBalanceOf[_lender].total,
            "Cannot redeem more than the lending amount provided."
        );
        lendingBalanceOf[_lender].total -= _amount;
        // _redeemCEthFromCompound(_amount, false); // false :we retrieve asset based on an amount of the asset
        // payable(_lender).transfer(_amount);
    }

    function _supplyEthToCompound(uint256 _amount) internal {
        cEthToken.mint{value: _amount}(); // Revert on error.
    }

    function _supplyDaiToCompound(uint256 _amount) internal {
        // Approve transfer on the ERC20 contract.
        daiToken.approve(CDAI_ADDRESS, _amount);
        // Mint cTokens.
        require(cDaiToken.mint(_amount) == 0, "Call to Compound failed.");
    }

    function _redeemCDaiFromCompound(uint256 _amount, bool _redeemType)
        internal
        returns(uint256 result)
    {
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cDaiToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cDaiToken.redeemUnderlying(_amount);
        }
    }

    function _redeemCEthFromCompound(uint256 _amount, bool _redeemType)
        internal
        returns(uint256 result)
    {
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cEthToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cEthToken.redeemUnderlying(_amount);
        }
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
        require(remainingLiquidityToUse == 0, "Not enough liquidity to use.");
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
        require(
            remainingLiquidityToUnuse == 0,
            "Not enough liquidity to unuse."
        );
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
