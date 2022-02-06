// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {IAToken} from "../interfaces/aave/IAToken.sol";
import "../interfaces/aave/IPriceOracleGetter.sol";
import "../interfaces/aave/IFlashLoanReceiver.sol";
import "../interfaces/aave/ILendingPoolAddressesProvider.sol";
import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../PositionsManagerForAave.sol";
import "../libraries/math/PercentageMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidatorForAave is Ownable, IFlashLoanReceiver {
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    ///  Storage  ///

    PositionsManagerForAave public immutable positionsManager;
    ISwapRouter public immutable uniswapRouter;
    ILendingPoolAddressesProvider public immutable addressesProvider;
    ILendingPool public lendingPool;

    ///  Structs  ///

    struct FlashLoanParams {
        address receiverAddress;
        address[] marketsToLoan;
        uint256[] amounts;
        uint256[] modes;
        uint24 fees;
        bytes data;
    }

    struct LiquidationParams {
        address collateralAsset; // the address of the collateral underlying
        address borrowedAsset; // the address of the borrowed (debt) underlying
        address poolTokenCollateralAddress; // the address of the pool token corresponding to the collateral asset
        address poolTokenBorrowedAddress; // the address of the pool token correspondinf to the borrowed asset
        address borrower; // the borrower address
        uint256 debtToCover; // the amount of the debt to liquidate
        uint24 fees; // the fees corresponding to the uniswap swap of collateralAsset => borrowedAsset
    }

    struct LiquidationCallLocalVars {
        uint256 initFlashBorrowedBalance;
        uint256 diffFlashBorrowedBalance;
        uint256 initCollateralBalance;
        uint256 diffCollateralBalance;
        uint256 flashLoanDebt;
        uint256 soldAmount;
        uint256 remainingTokens;
        uint256 borrowedAssetLeftovers;
    }

    /// Events ///

    event Swap(
        address indexed _assetFrom,
        address indexed _addressTo,
        uint256 amountIn,
        uint256 amountOut,
        uint24 fees
    );

    event Withdraw(address indexed _asset, uint256 _amount);
    event Deposit(address indexed _sender, address indexed _asset, uint256 _amount);

    event Liquidated(
        address indexed _liquidator,
        address _borrower,
        address indexed _debtMarket,
        address indexed _poolTokenCollateralAddress,
        uint256 _amount,
        uint256 _amountRewarded // in collateral unit
    );

    /// @dev Emitted when the `lendingPool` is updated on the `liquidationForMorpho` contract.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolUpdated(address _lendingPoolAddress);

    /// Errors ///

    /// @notice Emitted if executeOperation is not called by the lending pool
    error CallerMustBeLendingPool();

    /// @notice Emitted when Flash loan is not correctly set
    error InconsistentFlashLoansParams();

    /// @notice Emitted when the balance is below the amount to swap
    error AmountToSwapExceedMaxSlippage();

    /// Constructor ///

    /// @dev Constructs the LiquidatorForAave contract.
    /// @param _positionsManager The address of the Morpho positionsManager
    /// @param _swapRouter The address of the "Uniswap" V3 Router
    constructor(
        PositionsManagerForAave _positionsManager,
        ISwapRouter _swapRouter,
        ILendingPoolAddressesProvider _addressesProvider
    ) {
        positionsManager = _positionsManager;
        uniswapRouter = _swapRouter;
        addressesProvider = _addressesProvider;
        lendingPool = ILendingPool(_addressesProvider.getLendingPool());
    }

    /// @dev Updates the `lendingPool` contract from aave.
    function updateAaveContracts() external {
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
    }

    /**
     * Main Function
     * Liquidate a Morpho borrower with a flash swap
     *
     * @param _borrower (address): the Morpho borrower to liquidate
     * @param _repayPoolToken (address): a poolToken for which the borrower is in debt
     * @param _seizePoolToken (address): a poolToken for which the borrower has a supply balance
     * @param _amount (uint): the amount (specified in units of _repayPoolToken.underlying) to flash loan and pay off
     * @param _fees (uint): fees for swap 3000 for normalSwap, 1000 for stable swap, 5000 for exotic swap
     * @param _onBehalfOf (address): address where the funds will be send to. if is set to this contract, the contract will keep the funds
     */
    function liquidate(
        address _borrower,
        address _repayPoolToken,
        address _seizePoolToken,
        uint256 _amount,
        uint24 _fees,
        address _onBehalfOf
    ) public {
        // init assets
        address initiator = _onBehalfOf == address(0) ? msg.sender : _onBehalfOf;
        IERC20 debtToken = IERC20(IAToken(_repayPoolToken).UNDERLYING_ASSET_ADDRESS());
        IERC20 collateralToken = IERC20(IAToken(_seizePoolToken).UNDERLYING_ASSET_ADDRESS());
        uint256 debtBalanceBefore = debtToken.balanceOf(address(this));
        uint256 collateralBalanceBefore = collateralToken.balanceOf(address(this));
        uint256 rewarded;

        if ((initiator == address(this) || msg.sender == owner()) && debtBalanceBefore >= _amount) {
            // the contract will keep funds & have already enough funds to cover the debt
            // we do not need to use a flash swap

            // Liquidate the borrower position and release the underlying collateral
            positionsManager.liquidate(_repayPoolToken, _seizePoolToken, _borrower, _amount);
            rewarded = collateralToken.balanceOf(address(this)) - collateralBalanceBefore;
            emit Liquidated(
                msg.sender,
                _borrower,
                _repayPoolToken,
                _seizePoolToken,
                _amount,
                rewarded
            );
        } else {
            // Initiate flash loan params
            FlashLoanParams memory flashLoansParams;

            flashLoansParams.marketsToLoan = new address[](1);
            flashLoansParams.marketsToLoan[0] = address(debtToken);
            flashLoansParams.receiverAddress = address(this);

            // Transfer data to proceed to the liquidation
            flashLoansParams.data = abi.encode(
                address(collateralToken),
                address(debtToken),
                _seizePoolToken,
                _repayPoolToken,
                _borrower,
                _amount,
                _fees
            );

            flashLoansParams.amounts = new uint256[](1);
            flashLoansParams.amounts[0] = _amount;

            flashLoansParams.fees = _fees;

            flashLoansParams.modes = new uint256[](1);
            flashLoansParams.modes[0] = uint256(0);

            lendingPool.flashLoan(
                flashLoansParams.receiverAddress,
                flashLoansParams.marketsToLoan,
                flashLoansParams.amounts,
                flashLoansParams.modes,
                flashLoansParams.receiverAddress, // onBehalfOf
                flashLoansParams.data,
                0
            );

            // withdraw liquidated amount to the liquidator
            rewarded = collateralToken.balanceOf(address(this)) - collateralBalanceBefore;

            emit Liquidated(
                msg.sender,
                _borrower,
                _repayPoolToken,
                _seizePoolToken,
                _amount,
                rewarded
            );
        }
        uint256 debtBalanceAfter = debtToken.balanceOf(address(this));
        if (initiator != address(this) && debtBalanceBefore < debtBalanceAfter)
            // withdraw if there is dust on debtToken
            debtToken.safeTransfer(initiator, debtBalanceAfter - debtBalanceBefore);

        // transfer rewarded funds to the initiator if needed
        if (initiator != address(this)) collateralToken.safeTransfer(initiator, rewarded);
    }

    /**
    * @notice Function called by Flash loans execution
    * @param assets : assets that recieved a flash loans
    * @param amounts : corresponding flashed amounts
    * @param premiums : fees for each flash loan, corresponding to 0.09% of the amount flashed
    * @param initiator : address to the caller
    $ @param params : encoded params transfered for liquidation & swap call
    **/
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(lendingPool)) revert CallerMustBeLendingPool();

        LiquidationParams memory decodedParams = _decodeParams(params);

        if (assets.length != 1 || assets[0] != decodedParams.borrowedAsset)
            revert InconsistentFlashLoansParams();

        LiquidationCallLocalVars memory vars;
        uint256 flashBorrowedAmount = amounts[0];
        uint256 premium = premiums[0];

        vars.initCollateralBalance = IERC20(decodedParams.collateralAsset).balanceOf(address(this));
        if (decodedParams.collateralAsset != decodedParams.borrowedAsset) {
            vars.initFlashBorrowedBalance = IERC20(decodedParams.borrowedAsset).balanceOf(
                address(this)
            );

            // Track leftover balance to rescue funds in case of external transfers into this contract
            vars.borrowedAssetLeftovers = vars.initFlashBorrowedBalance - flashBorrowedAmount;
        }
        vars.flashLoanDebt = flashBorrowedAmount + premium;

        // Approve LendingPool to use debt token for liquidation
        IERC20(decodedParams.borrowedAsset).approve(
            address(lendingPool),
            decodedParams.debtToCover
        );

        // Liquidate the borrower position and release the underlying collateral
        positionsManager.liquidate(
            decodedParams.poolTokenBorrowedAddress,
            decodedParams.poolTokenCollateralAddress,
            decodedParams.borrower,
            decodedParams.debtToCover
        );

        // Discover the liquidated tokens
        uint256 collateralBalanceAfter = IERC20(decodedParams.collateralAsset).balanceOf(
            address(this)
        );

        // Track only collateral released, not current asset balance of the contract
        vars.diffCollateralBalance = collateralBalanceAfter - vars.initCollateralBalance;

        if (decodedParams.collateralAsset != decodedParams.borrowedAsset) {
            // Discover flash loan balance after the liquidation
            uint256 flashBorrowedAssetAfter = IERC20(decodedParams.borrowedAsset).balanceOf(
                address(this)
            );

            // Use only flash loan borrowed assets, not current asset balance of the contract
            vars.diffFlashBorrowedBalance = flashBorrowedAssetAfter - vars.borrowedAssetLeftovers;
            uint256 amountToSwap = vars.flashLoanDebt - vars.diffFlashBorrowedBalance;
            // Swap released collateral into the debt asset, to repay the flash loan
            vars.soldAmount = _swapTokensForExactTokens(
                decodedParams.collateralAsset,
                decodedParams.borrowedAsset,
                vars.diffCollateralBalance,
                amountToSwap,
                decodedParams.fees
            );
            emit Swap(
                decodedParams.collateralAsset,
                decodedParams.borrowedAsset,
                vars.soldAmount,
                amountToSwap,
                decodedParams.fees
            );
            vars.remainingTokens =
                IERC20(decodedParams.borrowedAsset).balanceOf(address(this)) -
                vars.flashLoanDebt;
        } else {
            vars.remainingTokens = vars.diffCollateralBalance - premium;
        }

        // Allow repay of flash loan
        IERC20(decodedParams.borrowedAsset).approve(address(lendingPool), vars.flashLoanDebt);

        return true;
    }

    /// @dev withdraw rewarded tokens (only owner)
    function withdraw(address _assetAddress, uint256 _amount) external onlyOwner {
        uint256 contractBalance = IERC20(_assetAddress).balanceOf(address(this));
        uint256 amount = contractBalance >= _amount ? _amount : contractBalance;

        IERC20(_assetAddress).safeTransfer(owner(), amount);
        emit Withdraw(_assetAddress, amount);
    }

    /// @notice add funds to prevent flash swap use and save fees.
    /// @dev this funds can be only withdraw by the contract owner.
    function addFunds(address _assetAddress, uint256 _amount) external {
        IERC20(_assetAddress).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _assetAddress, _amount);
    }

    /// @dev Executed when a liquidation has occured, and liquidator need to repay the flash loan
    /// @param assetToSwapFrom (address) the collateral asset of the swap
    /// @param assetToSwapTo (address) the debt asset & the flash loaned asset
    /// @param maxAmountToSwap (uint256) the amount rewarded by the flash loan
    /// @param amountToReceive (uint256) the exact amount to receive, corresponding to flash loan amount + flash loan fees
    /// @param fees (uint24) the fees for the transfer, which depends of the type of swap
    function _swapTokensForExactTokens(
        address assetToSwapFrom,
        address assetToSwapTo,
        uint256 maxAmountToSwap,
        uint256 amountToReceive,
        uint24 fees
    ) internal returns (uint256 amountInSwapped) {
        uint256 fromAssetDecimals = _getDecimals(assetToSwapFrom);
        uint256 toAssetDecimals = _getDecimals(assetToSwapTo);

        uint256 fromAssetPrice = _getPrice(assetToSwapFrom);
        uint256 toAssetPrice = _getPrice(assetToSwapTo);
        uint256 amountToSwap = (amountToReceive.percentMul(
            PercentageMath.PERCENTAGE_FACTOR + ((fees + 1) / (10**2))
        ) *
            (10**fromAssetDecimals) *
            toAssetPrice) / (fromAssetPrice * (10**toAssetDecimals)); // is a good method to add 0.01 % to prevent reverted swap ?

        if (amountToSwap > maxAmountToSwap) revert AmountToSwapExceedMaxSlippage();

        // Approves the transfer for the swap.
        // Approves for 0 first to comply with tokens that implement the anti front running approval fix.
        IERC20(assetToSwapFrom).safeApprove(address(uniswapRouter), 0);
        IERC20(assetToSwapFrom).safeApprove(address(uniswapRouter), maxAmountToSwap);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: assetToSwapFrom,
            tokenOut: assetToSwapTo,
            fee: fees,
            recipient: address(this),
            deadline: block.timestamp,
            amountInMaximum: amountToSwap,
            amountOut: amountToReceive,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactOutputSingle` executes the swap. // amountIn is the amount swapped
        amountInSwapped = uniswapRouter.exactOutputSingle(params);
    }

    function _decodeParams(bytes memory params) internal pure returns (LiquidationParams memory) {
        (
            address collateralAsset,
            address borrowedAsset,
            address poolTokenCollateralAddress,
            address poolTokenBorrowedAddress,
            address borrower,
            uint256 debtToCover,
            uint24 fees
        ) = abi.decode(params, (address, address, address, address, address, uint256, uint24));

        return
            LiquidationParams(
                collateralAsset,
                borrowedAsset,
                poolTokenCollateralAddress,
                poolTokenBorrowedAddress,
                borrower,
                debtToCover,
                fees
            );
    }

    /**
     * @dev Get the price of the asset from the oracle denominated in eth
     * @param asset address
     * @return eth price for the asset
     */
    function _getPrice(address asset) internal view returns (uint256) {
        return IPriceOracleGetter(addressesProvider.getPriceOracle()).getAssetPrice(asset);
    }

    /**
     * @dev Get the decimals of an asset
     * @return number of decimals of the asset
     */
    function _getDecimals(address asset) internal view returns (uint256) {
        return IERC20Metadata(asset).decimals();
    }
}
