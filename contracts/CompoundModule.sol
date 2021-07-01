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
    mapping(address => Balance) public collateralBalanceOf; // Collateral balance of user (DAI/cDAI).
    mapping(address => uint256) public borrowingBalanceOf; // Borrowing balance of user (cETH).
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
        lendingBalanceOf[msg.sender].unused += msg.value * cEthToken.exchangeRateCurrent();
    }

    function borrow(uint256 _amount) external {
        // Calculate the collateral needed.
        uint daiAmountEquivalentToEthAmount = oracle.consult(
            WETH_ADDRESS,
            _amount,
            DAI_ADDRESS
        );
        uint collateralNeededInDai = (daiAmountEquivalentToEthAmount /
            DENOMINATOR) * COLLATERAL_FACTOR;
        // Calculate the collateral value of sender in DAI.
        uint exchangeRateCurrentDai = cDaiToken.exchangeRateCurrent();
        uint collateralValueInDAI = collateralBalanceOf[msg.sender].unused / exchangeRateCurrentDai;
        // Check is sender has enough collateral.
        require(collateralNeededInDai <= collateralValueInDAI, "Not enough collateral.");

        // Check if contract has the cTokens for the borrowing.
        uint amountInCEth = _amount * cEthToken.exchangeRateCurrent();
        require(
            amountInCEth <= cEthToken.balanceOf(address(this)),
            "Amount to borrow should be less than total available."
        );

        // Now contract can take liquidity thanks to cTokens.
        _findUnusedCTokensAndUse(amountInCEth);

        // Update used and unused collateral.
        collateralBalanceOf[msg.sender].unused -= collateralNeededInDai * exchangeRateCurrentDai; // In cToken.
        collateralBalanceOf[msg.sender].used += collateralNeededInDai; // In underlying.
        borrowingBalanceOf[msg.sender] += amountInCEth; // In cToken.

        // Transfer ETH to borrower
        payable(msg.sender).transfer(_amount);
    }

    function payBackAll() external payable {
        uint amountInCEth = msg.value * cEthToken.exchangeRateCurrent();
        require(
            amountInCEth >= borrowingBalanceOf[msg.sender],
            "Must payback all the debt."
        );
        payable(address(this)).transfer(msg.value);
        _supplyEthToCompound(msg.value);
        _findUsedCTokensAndUnuse(amountInCEth);
        borrowingBalanceOf[msg.sender] = 0;
    }

    function cashOut(uint256 _amount) external {
        _cashOut(msg.sender, _amount);
    }

    function provideCollateral(uint256 _amount) external payable {
        require(_amount > 0, "Amount cannot be 0");
        daiToken.approve(address(this), _amount);
        daiToken.transferFrom(msg.sender, address(this), _amount);
        _supplyDaiToCompound(_amount);
        // Update the collateral balance of the sender in cDAI.
        collateralBalanceOf[msg.sender].unused += _amount * cDaiToken.exchangeRateCurrent(); // In cToken.
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
        } else {
            // Update used and unused of `_lender`
            uint amountInCEth = _amount * cEthToken.exchangeRateCurrent();
            lendingBalanceOf[_lender].unused += amountInCEth; // In cToken.
            lendingBalanceOf[_lender].used -= _amount; // In underlying.
            if (cEthToken.balanceOf(address(this)) > 0) {
                _findUnusedCTokensAndUse(amountInCEth);
                _redeemLending(_lender, _amount);
            } else {
                // TODO: what happens after borrowing?
                cEthToken.borrow(_amount);
                borrowingBalanceOf[_lender] += amountInCEth;
                payable(_lender).transfer(_amount);
            }
        }
        delete currentLenders[lenderToIndex[_lender]];
    }

    function _redeemCollateral(address _borrower, uint256 _amount) internal {
        require(
            borrowingBalanceOf[_borrower] == 0,
            "Borrowing must be repaid before redeeming collateral."
        );
        uint amountInCDai = _amount * cDaiToken.exchangeRateCurrent();
        require(amountInCDai <= collateralBalanceOf[msg.sender].unused, "Amount to redeem must be less than collateral.");
        require(_redeemCDaiFromCompound(_amount, false) == 0, "Redeem cDAI on Compound failed.");
        collateralBalanceOf[msg.sender].unused -= amountInCDai; // In cToken.
        daiToken.transferFrom(address(this), _borrower, _amount);
    }

    // Amount in cETH.
    function _redeemLending(address _lender, uint256 _amount) internal {
        uint amountInCEth = _amount * cEthToken.exchangeRateCurrent();
        require(
            amountInCEth <= lendingBalanceOf[_lender].unused,
            "Cannot redeem more than the lending amount provided."
        );
        // Update unused lending balance of `_lender`.
        lendingBalanceOf[_lender].unused -= amountInCEth; // In cToken.
        _redeemCEthFromCompound(_amount, false);
        payable(_lender).transfer(_amount);
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

    // If false pass DAI, if true pass cDAI
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

    // If false pass ETH, if true pass cETH
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

    // Amount in cToken.
    function _findUnusedCTokensAndUse(uint256 _amount) internal {
        uint remainingLiquidityToUse = _amount;
        uint i;
        while (remainingLiquidityToUse > 0 && i < currentLenders.length) {
            address lenderAddress = currentLenders[i];
            uint unused = lendingBalanceOf[lenderAddress].unused;

            if (unused > 0) {
                uint amountToUse = min(unused, remainingLiquidityToUse); // In cToken.
                lendingBalanceOf[lenderAddress].used += amountToUse / cEthToken.exchangeRateCurrent(); // In underlying.
                remainingLiquidityToUse -= amountToUse; // In underlying.
            }
            i++;
        }
        require(remainingLiquidityToUse == 0, "Not enough liquidity to use.");
    }

    // Amount in cToken.
    function _findUsedCTokensAndUnuse(uint256 _amount) internal {
        uint remainingLiquidityToUnuse = _amount;
        uint i;
        while (remainingLiquidityToUnuse > 0 && i < currentLenders.length) {
            address lenderAddress = currentLenders[i];
            uint used = lendingBalanceOf[lenderAddress].used;

            if (used > 0) {
                uint amountToUnuse = min(
                    used,
                    remainingLiquidityToUnuse
                );
                lendingBalanceOf[lenderAddress].used -= amountToUnuse / cEthToken.exchangeRateCurrent(); // In underlying.
                remainingLiquidityToUnuse -= amountToUnuse; // In cToken.
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
