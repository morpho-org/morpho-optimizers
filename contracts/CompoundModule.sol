pragma solidity >=0.6.6;

import "./libraries/SafeMath.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import {ICErc20, ICEth} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending.
 */
contract CompoundModule {
    using SafeMath for uint;

    event MyLog(string, uint);

    /* Structs */

    struct Balance {
        uint256 unused; // In cToken.
        uint256 used; // In underlying Token.
    }

    /* Storage */

    mapping(address => Balance) public lendingBalanceOf; // Lending balance of user (ETH/cETH).
    mapping(address => Balance) public collateralBalanceOf; // Collateral balance of user (DAI/cDAI).
    mapping(address => uint256) public borrowingBalanceOf; // Borrowing balance of user (ETH).
    mapping(address => uint256) public lenderToIndex; // Position of the lender in the currentLenders list.
    address[] public currentLenders; // Current lenders in the protocol.
    uint256 public constant COLLATERAL_FACTOR = 10000; // Collateral factor in basis points 100% by default.
    uint256 public constant DENOMINATOR = 10000; // Collateral factor in basis points.
    uint256 public constant POWER = 28; // 18 + underlyingDecimals - cTokenDecimals = 18 + 18 - 8

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

    /** @dev Allows someone to lend ETH.
     *  @dev ETH is sent through msg.value.
     */
    function lend() external payable {
        _supplyEthToCompound(msg.value);
        if (lendingBalanceOf[msg.sender].unused == 0) {
            lenderToIndex[msg.sender] = currentLenders.length;
            currentLenders.push(msg.sender);
        }
        lendingBalanceOf[msg.sender].unused += msg.value.mul(10**POWER).div(cEthToken.exchangeRateCurrent()); // In cToken.
    }

    /** @dev Allows someone to borrow ETH.
     *  @param _amount Amount to borrow in ETH.
     */
    function borrow(uint256 _amount) external {
        // Calculate the collateral needed.
        uint256 daiAmountEquivalentToEthAmount = oracle.consult(
            WETH_ADDRESS,
            _amount,
            DAI_ADDRESS
        );
        uint256 collateralNeededInDai = daiAmountEquivalentToEthAmount.mul(COLLATERAL_FACTOR).div(COLLATERAL_FACTOR);
        // Calculate the collateral value of sender in DAI.
        uint256 collateralNeededInCDai = collateralNeededInDai.mul(10**POWER).div(cDaiToken.exchangeRateCurrent());
        // Check if sender has enough collateral.
        require(
            collateralNeededInDai <= collateralBalanceOf[msg.sender].unused,
            "Not enough collateral."
        );
        // Check if contract has the cTokens for the borrowing.
        uint256 amountInCEth = _amount.mul(10**POWER).div(cEthToken.exchangeRateCurrent());
        require(
            amountInCEth <= cEthToken.balanceOf(address(this)),
            "Borrowing amount must be less than total available."
        );
        // Now contract can take liquidity thanks to cTokens.
        _findUnusedCTokensAndUse(amountInCEth, msg.sender);
        // Update used and unused collateral.
        collateralBalanceOf[msg.sender].unused -= collateralNeededInCDai; // In cToken.
        collateralBalanceOf[msg.sender].used += collateralNeededInDai; // In underlying.
        borrowingBalanceOf[msg.sender] += _amount; // In underlying.
        // Transfer ETH to borrower
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows someone to pay back its debt in ETH.
     *  @dev ETH is sent as msg.value.
     */
    function payBack() external payable {
        uint256 amountInCEth = msg.value.mul(10**POWER).div(cEthToken.exchangeRateCurrent());
        borrowingBalanceOf[msg.sender] -= msg.value;
        _findUsedCTokensAndUnuse(amountInCEth, msg.sender);
        _supplyEthToCompound(msg.value);
    }

    /** @dev Allows a lender to cash-out.
     *  @param _amount Amount in ETH to cash-out.
     */
    function cashOut(uint256 _amount) external {
        _cashOut(msg.sender, _amount);
    }

    /** @dev Allows a borrower to provide collateral in DAI.
     *  @param _amount Amount in DAI to provide.
     */
    function provideCollateral(uint256 _amount) external {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.approve(address(this), _amount);
        daiToken.transferFrom(msg.sender, address(this), _amount);
        _supplyDaiToCompound(_amount);
        // Update the collateral balance of the sender in cDAI.
        collateralBalanceOf[msg.sender].unused += _amount.mul(10**POWER).div(cDaiToken.exchangeRateCurrent()); // In cToken.
    }

    /** @dev Allows a borrower to redeem its collateral in DAI.
     *  @param _amount Amount in DAI to get back.
     */
    function redeemCollateral(uint256 _amount) external {
        _redeemCollateral(msg.sender, _amount);
    }

    /** @dev Allows somone to liquidate a position.
     *  @param _borrower The address of the borrowe to liquidate.
     */
    function liquidate(address _borrower) external payable {
        // TODO: write function
    }

    /* Internal */

    /** @dev Implements cash-out's logic for a `_lender`.
     *  @param _lender Address of the lender to cash-out its position.
     *  @param _amount Amount in ETH to cash-out.
     */
    function _cashOut(address _lender, uint256 _amount) internal {
        if (_amount <= lendingBalanceOf[_lender].unused) {
            _cashOutUnused(_lender, _amount);
        } else {
            uint256 unusedInEth = lendingBalanceOf[_lender].unused.mul(cEthToken.exchangeRateCurrent()).div(10**POWER);
            _cashOutUnused(_lender, unusedInEth);
            uint256 amountToCashOutInCEth = lendingBalanceOf[_lender].unused - _amount.mul(10**POWER).div(cEthToken.exchangeRateCurrent()); // In cToken.
            uint256 amountToCashOutInEth = amountToCashOutInCEth.mul(cEthToken.exchangeRateCurrent()).div(10**POWER);
            if (cEthToken.balanceOf(address(this)) > amountToCashOutInCEth) {
                _findUnusedCTokensAndUse(amountToCashOutInCEth, _lender);
                lendingBalanceOf[_lender].used -= amountToCashOutInEth; // In underlying.
                payable(_lender).transfer(amountToCashOutInEth);
            } else {
                // TODO: find borrower to unused.
                cEthToken.borrow(_amount);
                payable(_lender).transfer(_amount);
            }
        }
        // If lender has no lending at all, then remove it from the list of lenders.
        if (
            lendingBalanceOf[_lender].unused == 0 &&
            lendingBalanceOf[_lender].used == 0
        ) {
            delete currentLenders[lenderToIndex[_lender]];
        }
    }

    /** @dev Implements collateral redeeming's logic for a `_borrower`.
     *  @param _borrower Address of the borrower to redeem collateral for.
     *  @param _amount Amount in DAI to redeem.
     */
    function _redeemCollateral(address _borrower, uint256 _amount) internal {
        require(
            borrowingBalanceOf[_borrower] == 0,
            "Borrowing must be repaid before redeeming collateral."
        );
        uint256 amountInCDai = _amount.mul(10**POWER).div(cDaiToken.exchangeRateCurrent());
        require(
            amountInCDai <= collateralBalanceOf[msg.sender].unused,
            "Amount to redeem must be less than collateral."
        );
        require(
            _redeemDaiFromCompound(_amount, false) == 0,
            "Redeem cDAI on Compound failed."
        );
        collateralBalanceOf[msg.sender].unused -= amountInCDai; // In cToken.
        daiToken.transfer(_borrower, _amount);
    }

    /** @dev Cashes-out `_lender`'s unused tokens.
     *  @param _lender Address of the lender to redeem lending for.
     *  @param _amount Amount in ETH to redeem.
     */
    function _cashOutUnused(address _lender, uint256 _amount) internal {
        uint256 amountInCEth = _amount.mul(10**POWER).div(cEthToken.exchangeRateCurrent());
        require(
            amountInCEth <= lendingBalanceOf[_lender].unused,
            "Cannot redeem more than the lending amount provided."
        );
        // Update unused lending balance of `_lender`.
        lendingBalanceOf[_lender].unused -= amountInCEth; // In cToken.
        _redeemEthFromCompound(_amount, false);
        payable(_lender).transfer(_amount);
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
                    lendingBalanceOf[lender].used += amountToUse.mul(cEthToken.exchangeRateCurrent()).div(10**POWER); // In underlying.
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
                    );
                    lendingBalanceOf[lender].used -= amountToUnuse.mul(cEthToken.exchangeRateCurrent()).div(10**POWER); // In underlying.
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {}
}
