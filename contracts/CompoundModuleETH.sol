pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IOracle.sol";
import {ICErc20, ICEth, ICToken, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";

/**
 *  @title CompoundModuleETH
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with ETH as collateral.
 */
contract CompoundModuleETH is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* Structs */

    struct LendingBalance {
        uint256 onComp; // In cToken.
        uint256 onMorpho; // In mUnit (a unit that grows in value, to follow debt increase).
    }

    struct BorrowingBalance {
        uint256 onMorpho; // In underlying.
        uint256 onComp; // In underlying.
    }

    /* Storage */

    mapping(address => LendingBalance) public lendingBalanceOf; // Lending balance of user (DAI/cDAI).
    mapping(address => BorrowingBalance) public borrowingBalanceOf; // Borrowing balance of user (DAI).
    mapping(address => uint256) public collateralBalanceOf; // Collateral balance of user (cETH).
    EnumerableSet.AddressSet private lenders; // Lenders on Morpho.
    EnumerableSet.AddressSet private borrowersOnMorpho; // Borrowers on Morpho.
    EnumerableSet.AddressSet private borrowersOnComp; // Borrowers on Compound.
    uint256 public collateralFactor = 75e16; // Collateral Factor related to cETH.
    uint256 public liquidationIncentive = 8000; // Incentive for liquidators in percentage in basis points.

    uint256 public BPY; // Block Percentage Yield ("midrate").
    uint256 public currentExchangeRate; // current exchange rate from mUnit to underlying.
    uint256 public lastUpdateBlockNumber; // Last time currentExchangeRate was updated.

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
    address public constant COMPOUND_ORACLE_ADDRESS =
        0x841616a5CBA946CF415Efe8a326A621A794D0f97;

    IComptroller public comptroller = IComptroller(PROXY_COMPTROLLER_ADDRESS);
    ICEth public cEthToken = ICEth(CETH_ADDRESS);
    ICErc20 public cDaiToken = ICErc20(CDAI_ADDRESS);
    IERC20 public daiToken = IERC20(DAI_ADDRESS);
    IOracle public oracle = IOracle(ORACLE_ADDRESS);
    ICompoundOracle public compoundOracle =
        ICompoundOracle(COMPOUND_ORACLE_ADDRESS);

    /* Contructor */

    constructor() {
        updateBPY();
        lastUpdateBlockNumber = block.number;
        currentExchangeRate = 1e18;
    }

    /* External */

    /** @dev Allows someone to lend DAI.
     *  @param _amount The amount to lend in DAI.
     */
    function lend(uint256 _amount) external {
        require(_amount > 0, "Amount cannot be 0");
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = (_moveBorrowersFromCompToMorpho(
                _amount
            ) * 1e18) / cDaiExchangeRate;
            // Repay Compound.
            cDaiToken.repayBorrow(_amount - remainingToSupplyToComp); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                ((_amount - remainingToSupplyToComp) * 1e18) /
                _updateCurrentExchangeRate(); // In mUnit.
            lendingBalanceOf[msg.sender].onComp +=
                (remainingToSupplyToComp * cDaiExchangeRate) /
                1e18; // In cToken.
            if (remainingToSupplyToComp > 0)
                _supplyDaiToComp(remainingToSupplyToComp);
        } else {
            lendingBalanceOf[msg.sender].onComp +=
                (_amount * 1e18) /
                cDaiExchangeRate; // In cToken.
            _supplyDaiToComp(_amount);
        }
    }

    /** @dev Allows someone to directly stake cDAI.
     *  @param _amount The amount to stake in cDAI.
     */
    function stake(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount cannot be 0");
        lenders.add(msg.sender); // Return false when lender is already there. O(1)
        cDaiToken.transferFrom(msg.sender, address(this), _amount);
        // If some borrowers are on Compound, we must move them to Morpho.
        if (borrowersOnComp.length() > 0) {
            uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
            uint256 amounInDai = (_amount * cDaiExchangeRate) / 1e18;
            // Find borrowers and move them to Morpho.
            uint256 remainingToSupplyToComp = (_moveBorrowersFromCompToMorpho(
                amounInDai
            ) * 1e18) / cDaiExchangeRate;
            _redeemDaiFromComp(remainingToSupplyToComp, false);
            // Repay Compound.
            cDaiToken.repayBorrow(amounInDai - remainingToSupplyToComp); // Revert on error.
            // Update lender balance.
            lendingBalanceOf[msg.sender].onMorpho +=
                ((_amount - remainingToSupplyToComp) * cDaiExchangeRate) /
                _updateCurrentExchangeRate(); // In mUnit.
            lendingBalanceOf[msg.sender].onComp += remainingToSupplyToComp;
        } else {
            lendingBalanceOf[msg.sender].onComp += _amount; // In cToken.
        }
    }

    /** @dev Allows someone to borrow DAI.
     *  @param _amount The amount to borrow in DAI.
     */
    function borrow(uint256 _amount) external nonReentrant {
        // Calculate the collateral required.
        require(_amount > 0, "Amount cannot be 0");
        uint256 ethPriceMantissa = compoundOracle.getUnderlyingPrice(
            ICToken(CETH_ADDRESS)
        );
        uint256 daiPriceMantissa = compoundOracle.getUnderlyingPrice(
            ICToken(CDAI_ADDRESS)
        );
        require(
            ethPriceMantissa != 0 && daiPriceMantissa != 0,
            "Oracle failed."
        );
        uint256 numerator = _amount * daiPriceMantissa * collateralFactor;
        uint256 denominator = ethPriceMantissa *
            cEthToken.exchangeRateCurrent();
        uint256 collateralRequiredInCEth = numerator / denominator;
        // Check if borrower has enough collateral.
        require(
            collateralRequiredInCEth <= collateralBalanceOf[msg.sender],
            "Not enough collateral."
        );
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 amountInCDai = (_amount * 1e18) / cDaiExchangeRate;
        uint256 remainingToBorrowOnComp = (_moveLendersFromCompToMorpho(
            amountInCDai,
            msg.sender
        ) * cDaiExchangeRate) / 1e18; // In underlying.
        borrowingBalanceOf[msg.sender].onMorpho +=
            _amount -
            remainingToBorrowOnComp; // In underlying.
        // If not enough cTokens on Morpho, we must borrow it on Compound.
        if (remainingToBorrowOnComp > 0) {
            cDaiToken.borrow(remainingToBorrowOnComp); // Revert on error.
            borrowingBalanceOf[msg.sender].onComp += remainingToBorrowOnComp; // In underlying.
            borrowersOnComp.add(msg.sender);
            if (remainingToBorrowOnComp != _amount)
                borrowersOnMorpho.add(msg.sender);
        }
        _redeemDaiFromComp(_amount - remainingToBorrowOnComp, false);
        // Transfer DAI to borrower.
        daiToken.safeTransfer(msg.sender, _amount);
    }

    /** @dev Allows a borrower to pay back its debt in DAI.
     *  @param _amount The amount in DAI to payback.
     */
    function payBack(uint256 _amount) external nonReentrant {
        _payBack(msg.sender, _amount);
    }

    /** @dev Allows a lender to cash-out her DAI.
     *  @param _amount The amount in DAI to cash-out.
     */
    function cashOut(uint256 _amount) external nonReentrant {
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 amountOnCompInDai = (lendingBalanceOf[msg.sender].onComp *
            cDaiExchangeRate) / 1e18;
        if (_amount <= amountOnCompInDai) {
            lendingBalanceOf[msg.sender].onComp -=
                (_amount * 1e18) /
                cEthToken.exchangeRateCurrent(); // In cToken.
            _redeemDaiFromComp(_amount, false);
        } else {
            lendingBalanceOf[msg.sender].onComp = 0;
            _redeemDaiFromComp(amountOnCompInDai, false);
            uint256 remainingToCashOutInDai = _amount - amountOnCompInDai; // In underlying.
            lendingBalanceOf[msg.sender].onMorpho -=
                (remainingToCashOutInDai * 1e18) /
                _updateCurrentExchangeRate(); // In mUnit.
            uint256 remainingToCashOutInCDai = (remainingToCashOutInDai *
                1e18) / cDaiExchangeRate;
            uint256 cDaiContractBalance = cDaiToken.balanceOf(address(this));
            if (remainingToCashOutInCDai <= cDaiContractBalance) {
                _moveLendersFromCompToMorpho(
                    remainingToCashOutInCDai,
                    msg.sender
                );
            } else {
                _moveLendersFromCompToMorpho(cDaiContractBalance, msg.sender);
                remainingToCashOutInCDai -= cDaiContractBalance;
                remainingToCashOutInCDai -=
                    (_moveBorrowersFromMorphoToComp(remainingToCashOutInCDai) *
                        1e18) /
                    cDaiExchangeRate;
                cDaiToken.borrow(
                    (remainingToCashOutInCDai * cDaiExchangeRate) / 1e18
                ); // Revert on error.
            }
        }
        daiToken.safeTransfer(msg.sender, _amount);
        // If lender has no lending at all, then remove her from `lenders`.
        if (
            lendingBalanceOf[msg.sender].onComp == 0 &&
            lendingBalanceOf[msg.sender].onMorpho == 0
        ) {
            lenders.remove(msg.sender);
        }
    }

    /** @dev Allows a lender to unstake its cDAI.
     *  @param _amount Amount in cDAI to unstake.
     */
    function unstake(uint256 _amount) external nonReentrant {
        if (_amount <= lendingBalanceOf[msg.sender].onComp) {
            lendingBalanceOf[msg.sender].onComp -= _amount;
        } else {
            uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
            uint256 remainingToUnstakeInCDai = _amount -
                lendingBalanceOf[msg.sender].onComp;
            lendingBalanceOf[msg.sender].onComp = 0;
            lendingBalanceOf[msg.sender].onMorpho -=
                (remainingToUnstakeInCDai * cDaiExchangeRate) /
                _updateCurrentExchangeRate(); // In mUnit.
            uint256 cDaiContractBalance = cDaiToken.balanceOf(address(this));
            if (remainingToUnstakeInCDai <= cDaiContractBalance) {
                _moveLendersFromCompToMorpho(
                    remainingToUnstakeInCDai,
                    msg.sender
                );
            } else {
                _moveLendersFromCompToMorpho(cDaiContractBalance, msg.sender);
                remainingToUnstakeInCDai -= cDaiContractBalance;
                remainingToUnstakeInCDai -=
                    (_moveBorrowersFromMorphoToComp(remainingToUnstakeInCDai) *
                        1e18) /
                    cDaiExchangeRate;
                cDaiToken.borrow(
                    (remainingToUnstakeInCDai * cDaiExchangeRate) / 1e18
                ); // Revert on error.
            }
        }
        cDaiToken.transfer(msg.sender, _amount);
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
        require(msg.value > 0, "Amount cannot be 0");
        payable(address(this)).transfer(msg.value);
        _supplyEthToComp(msg.value);
        // Update the collateral balance of the sender in cETH.
        collateralBalanceOf[msg.sender] +=
            (msg.value * 1e18) /
            cEthToken.exchangeRateCurrent();
    }

    /** @dev Allows a borrower to redeem her collateral in ETH.
     *  @param _amount The amount in ETH to get back.
     */
    function redeemCollateral(uint256 _amount) external nonReentrant {
        uint256 cEthExchangeRate = cEthToken.exchangeRateCurrent();
        uint256 amountInCEth = (_amount * 1e18) / cEthExchangeRate;
        require(
            amountInCEth <= collateralBalanceOf[msg.sender],
            "Must redeem less than collateral."
        );
        uint256 collateralRequiredInEth = getCollateralRequired(
            borrowingBalanceOf[msg.sender].onComp,
            borrowingBalanceOf[msg.sender].onMorpho,
            collateralFactor,
            CETH_ADDRESS,
            CDAI_ADDRESS
        );
        uint256 collateralRequiredInCEth = (collateralRequiredInEth * 1e18) /
            cEthExchangeRate;
        uint256 collateralAfterInCEth = collateralBalanceOf[msg.sender] -
            amountInCEth;
        require(
            collateralAfterInCEth >= collateralRequiredInCEth,
            "Not enough collateral to maintain position."
        );
        require(
            _redeemEthFromComp(_amount, false) == 0,
            "Redeem cETH on Compound failed."
        );
        collateralBalanceOf[msg.sender] -= amountInCEth; // In cToken.
        payable(msg.sender).transfer(_amount);
    }

    /** @dev Allows someone to liquidate a position.
     *  @param _borrower The address of the borrower to liquidate.
     *  @param _amount The amount to repay in DAI.
     */
    function liquidate(address _borrower, uint256 _amount)
        external
        nonReentrant
    {
        (
            uint256 collateralInEth,
            uint256 collateralRequiredInEth
        ) = getAccountLiquidity(_borrower);
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        require(
            collateralInEth < collateralRequiredInEth,
            "Borrower position cannot be liquidated."
        );
        _payBack(_borrower, _amount);
        // Calculate the amount of token to seize from collateral.
        uint256 ethPriceMantissa = compoundOracle.getUnderlyingPrice(
            ICToken(CETH_ADDRESS)
        );
        uint256 daiPriceMantissa = compoundOracle.getUnderlyingPrice(
            ICToken(CDAI_ADDRESS)
        );
        require(
            ethPriceMantissa != 0 && daiPriceMantissa != 0,
            "Oracle failed."
        );
        uint256 numerator = _amount *
            daiPriceMantissa *
            collateralInEth *
            liquidationIncentive;
        uint256 totalBorrowingBalance = borrowingBalanceOf[_borrower].onMorpho +
            borrowingBalanceOf[_borrower].onComp;
        uint256 denominator = totalBorrowingBalance *
            ethPriceMantissa *
            DENOMINATOR;
        uint256 ethAmountToSeize = numerator / denominator;
        uint256 cEthAmountToSeize = (ethAmountToSeize * 1e18) /
            cEthToken.exchangeRateCurrent();
        require(
            cEthAmountToSeize <= collateralBalanceOf[_borrower],
            "Cannot get more than collateral balance of borrower."
        );
        collateralBalanceOf[_borrower] -= cEthAmountToSeize;
        _redeemEthFromComp(ethAmountToSeize, false);
        payable(msg.sender).transfer(ethAmountToSeize);
    }

    /** @dev Updates the collateral factor related to cDAI.
     */
    function updateCollateralFactor() external {
        (, collateralFactor, ) = comptroller.markets(CDAI_ADDRESS);
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
        collateralRequiredInEth = getCollateralRequired(
            borrowingBalanceOf[_borrower].onComp,
            borrowingBalanceOf[_borrower].onMorpho,
            collateralFactor,
            CDAI_ADDRESS,
            CETH_ADDRESS
        );
        collateralInEth =
            (collateralBalanceOf[_borrower] * cEthToken.exchangeRateCurrent()) /
            1e18;
    }

    /** @dev Returns the collateral required for the given parameters.
     *  @param _borrowedAmountOnCompound The amount of tokens borrowed that are on Compound.
     *  @param _borrowedAmountOnMorpho The amount of token borrowed that are on Morpho.
     *  @param _collateralFactor The collateral factor linked to the token borrowed.
     *  @param _borrowedCTokenAddress The address of the cToken linked to the token borrowed.
     *  @param _collateralCTokenAddress The address of the cToken linked to the token in collateral.
     *  @return collateralRequired The collateral required of the `_borrower`.
     */
    function getCollateralRequired(
        uint256 _borrowedAmountOnCompound,
        uint256 _borrowedAmountOnMorpho,
        uint256 _collateralFactor,
        address _borrowedCTokenAddress,
        address _collateralCTokenAddress
    ) public view returns (uint256) {
        uint256 borrowedAssetPriceMantissa = compoundOracle.getUnderlyingPrice(
            ICToken(_borrowedCTokenAddress)
        );
        uint256 collateralAssetPriceMantissa = compoundOracle
            .getUnderlyingPrice(ICToken(_collateralCTokenAddress));
        require(
            borrowedAssetPriceMantissa != 0 &&
                collateralAssetPriceMantissa != 0,
            "Oracle failed"
        );
        uint256 totalBorrowedAmount = _borrowedAmountOnCompound +
            _borrowedAmountOnMorpho; // In underlying
        uint256 numerator = totalBorrowedAmount *
            borrowedAssetPriceMantissa *
            _collateralFactor;
        uint256 denominator = collateralAssetPriceMantissa * 1e18;
        return numerator / denominator;
    }

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`currentExchangeRate`).
     */
    function updateBPY() public {
        // update BPY
        uint256 lendBPY = cDaiToken.borrowRatePerBlock();
        uint256 borrowBPY = cDaiToken.supplyRatePerBlock();
        BPY = (lendBPY + borrowBPY) / 2;

        // update currentExchangeRate
        _updateCurrentExchangeRate();
    }

    /* Internal */

    /** @dev Implements pay back logic.
     *  @param _borrower The address of the `_borrower` to pay back the borrowing.
     *  @param _amount The amount of DAI to pay back.
     */
    function _payBack(address _borrower, uint256 _amount) internal {
        if (borrowingBalanceOf[_borrower].onComp > 0) {
            if (_amount <= borrowingBalanceOf[_borrower].onComp) {
                // Repay Compound.
                borrowingBalanceOf[_borrower].onComp -= _amount;
                cDaiToken.repayBorrow(_amount); // Revert on error.
                _supplyDaiToComp(_amount);
            } else {
                // Repay Compound first.
                cDaiToken.repayBorrow(borrowingBalanceOf[_borrower].onComp); // Revert on error.
                // Then, move remaining and supply it to Compound.
                uint256 remainingToSupplyToComp = _amount -
                    borrowingBalanceOf[_borrower].onComp;
                uint256 remainingAmountToMoveInCDai = (remainingToSupplyToComp *
                    1e18) / cDaiToken.exchangeRateCurrent(); // In cToken.
                borrowingBalanceOf[_borrower]
                    .onMorpho -= remainingToSupplyToComp;
                borrowingBalanceOf[_borrower].onComp = 0;
                borrowersOnComp.remove(_borrower);
                _moveLendersFromMorphoToComp(
                    remainingAmountToMoveInCDai,
                    _borrower
                );
                _supplyDaiToComp(remainingToSupplyToComp);
            }
        } else {
            _moveLendersFromMorphoToComp(
                (_amount * 1e18) / cDaiToken.exchangeRateCurrent(),
                _borrower
            );
            borrowingBalanceOf[_borrower].onMorpho -= _amount;
            _supplyDaiToComp(_amount);
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
     *  @param _amount The amount to search for in cDAI.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     *  @return remainingToMove The remaining liquidity to search for in cDAI.
     */
    function _moveLendersFromCompToMorpho(
        uint256 _amount,
        address _lenderToAvoid
    ) internal returns (uint256 remainingToMove) {
        remainingToMove = _amount; // In cToken.
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 onComp = lendingBalanceOf[lender].onComp;

                if (onComp > 0) {
                    uint256 amountToMove = min(onComp, remainingToMove); // In cToken.
                    lendingBalanceOf[lender].onComp -= amountToMove; // In cToken.
                    lendingBalanceOf[lender].onMorpho +=
                        (amountToMove * cDaiExchangeRate) /
                        _updateCurrentExchangeRate(); // In mUnit.
                    remainingToMove -= amountToMove;
                }
            }
            i++;
        }
    }

    /** @dev Finds liquidity on Morpho and moves it to Compound.
     *  @param _amount The amount to search for in cDAI.
     *  @param _lenderToAvoid The address of the lender to avoid moving liquidity from.
     */
    function _moveLendersFromMorphoToComp(
        uint256 _amount,
        address _lenderToAvoid
    ) internal {
        uint256 remainingToMove = _amount; // In cToken.
        uint256 cDaiExchangeRate = cDaiToken.exchangeRateCurrent();
        uint256 i;
        while (remainingToMove > 0 && i < lenders.length()) {
            address lender = lenders.at(i);
            if (lender != _lenderToAvoid) {
                uint256 used = lendingBalanceOf[lender].onMorpho;

                if (used > 0) {
                    uint256 amountToMove = min(used, remainingToMove); // In cToken.
                    lendingBalanceOf[lender].onComp += amountToMove; // In cToken.
                    lendingBalanceOf[lender].onMorpho -=
                        (amountToMove * cDaiExchangeRate) /
                        _updateCurrentExchangeRate(); // In mUnit.
                    remainingToMove -= amountToMove; // In cToken.
                }
            }
            i++;
        }
        require(remainingToMove == 0, "Not enough liquidity to unuse.");
    }

    /** @dev Finds borrowers on Morpho that match the given `_amount` and moves them to Compound.
     *  @param _amount The amount to match in cDAI.
     */
    function _moveBorrowersFromMorphoToComp(uint256 _amount)
        internal
        returns (uint256 remainingToMatch)
    {
        remainingToMatch = _amount;
        uint256 i;
        while (remainingToMatch > 0 && i < borrowersOnMorpho.length()) {
            address borrower = borrowersOnMorpho.at(i);

            if (borrowingBalanceOf[borrower].onMorpho > 0) {
                uint256 toMatch = min(
                    borrowingBalanceOf[borrower].onMorpho,
                    remainingToMatch
                );
                remainingToMatch -= toMatch;
                borrowingBalanceOf[borrower].onComp += toMatch;
                borrowersOnComp.add(borrower);
            }
            i++;
        }
    }

    /** @dev Finds borrowers on Compound that match the given `_amount` and moves them to Morpho.
     *  @param _amount The amount to match in DAI.
     *  @return remainingToMatch The amount remaining to match in DAI.
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

    /** @dev Updates the current exchange rate, taking into the account block percentage yield since the last time it has been updated.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function _updateCurrentExchangeRate() internal returns (uint256) {
        // update currentExchangeRate.
        uint256 currentBlock = block.number;
        uint256 numberOfBlocksSinceLastUpdate = currentBlock -
            lastUpdateBlockNumber;
        currentExchangeRate =
            (currentExchangeRate *
                (1e18 + BPY * numberOfBlocksSinceLastUpdate)) /
            1e18;

        // update lastUpdateBlockNumber.
        lastUpdateBlockNumber = currentBlock;

        return currentExchangeRate;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    // This is needed to receive ETH when calling `_redeemEthFromComp`
    receive() external payable {}
}
