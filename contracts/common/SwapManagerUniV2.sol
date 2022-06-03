// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwapManager.sol";

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title SwapManager for Uniswap V2.
/// @notice Smart contract managing the swap of reward tokens to Morpho tokens.
contract SwapManagerUniV2 is ISwapManager, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPoint for *;

    /// STORAGE ///

    uint256 public twapInterval;
    uint256 public constant ONE_PERCENT = 100; // 1% in basis points.
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    address public immutable REWARD_TOKEN; // The reward token address.
    address public immutable MORPHO; // Morpho token address.
    address public immutable token0;
    address public immutable token1;

    IUniswapV2Router02 public immutable swapRouter;
    IUniswapV2Pair public immutable pair;

    /// EVENTS ///

    /// @notice Emitted when a swap to Morpho tokens happens.
    /// @param _receiver The address of the receiver.
    /// @param _amountIn The amount of reward token swapped.
    /// @param _amountOut The amount of Morpho token received.
    event Swapped(address indexed _receiver, uint256 _amountIn, uint256 _amountOut);

    /// @notice Emitted when the TWAP interval is set.
    /// @param _twapInterval The new `twapInterval`.
    event TwapIntervalSet(uint256 _twapInterval);

    /// ERRORS ///

    /// @notice Thrown when the TWAP interval is too short.
    error TwapTooShort();

    /// CONSTRUCTOR ///

    /// @notice Constructs the SwapManager contract.
    /// @param _swapRouter The swap router address.
    /// @param _morphoToken The Morpho token address.
    /// @param _rewardToken The reward token address.
    /// @param _twapInterval The interval for the Time-Weighted Average Price for the pair.
    constructor(
        address _swapRouter,
        address _morphoToken,
        address _rewardToken,
        uint256 _twapInterval
    ) {
        if (_twapInterval < 5 minutes) revert TwapTooShort();

        swapRouter = IUniswapV2Router02(_swapRouter);
        MORPHO = _morphoToken;
        REWARD_TOKEN = _rewardToken;
        twapInterval = _twapInterval;

        pair = IUniswapV2Pair(
            IUniswapV2Factory(swapRouter.factory()).getPair(_morphoToken, _rewardToken)
        );

        token0 = pair.token0();
        token1 = pair.token1();

        price0CumulativeLast = pair.price0CumulativeLast(); // Fetch the current accumulated price value (1 / 0).
        price1CumulativeLast = pair.price1CumulativeLast(); // Fetch the current accumulated price value (0 / 1).

        price0Average = FixedPoint.uq112x112(uint224(price0CumulativeLast));
        price1Average = FixedPoint.uq112x112(uint224(price1CumulativeLast));
    }

    /// EXTERNAL ///

    /// @notice Sets TWAP intervals.
    /// @param _twapInterval The new `twapInterval`.
    function setTwapIntervals(uint32 _twapInterval) external onlyOwner {
        if (_twapInterval < 5 minutes) revert TwapTooShort();
        twapInterval = _twapInterval;
        emit TwapIntervalSet(_twapInterval);
    }

    /// @dev Swaps reward tokens to Morpho tokens.
    /// @param _amountIn The amount of reward token to swap.
    /// @param _receiver The address of the receiver of the Morpho tokens.
    /// @return amountOut The amount of Morpho tokens sent.
    function swapToMorphoToken(uint256 _amountIn, address _receiver)
        external
        override
        returns (uint256 amountOut)
    {
        update();
        amountOut = consult(_amountIn);

        // Max slippage of 1% for the trade.
        uint256 expectedAmountOutMinimum = (amountOut * (MAX_BASIS_POINTS - ONE_PERCENT)) /
            MAX_BASIS_POINTS;

        address[] memory path = new address[](2);
        path[0] = REWARD_TOKEN;
        path[1] = MORPHO;

        // Execute the swap.
        ERC20(REWARD_TOKEN).safeApprove(address(swapRouter), _amountIn);
        uint256[] memory amountsOut = swapRouter.swapExactTokensForTokens(
            _amountIn,
            expectedAmountOutMinimum,
            path,
            _receiver,
            block.timestamp
        );

        amountOut = amountsOut[1];

        emit Swapped(_receiver, _amountIn, amountOut);
    }

    /// PUBLIC ///

    /// @notice Updates average prices on twapInterval fixed window.
    /// @dev From https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol
    function update() public {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint256 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint256 timeElapsed;

        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired.
        }

        // Ensure that at least one full period has passed since the last update.
        if (timeElapsed < twapInterval) return;

        // An overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed.
        unchecked {
            price0Average = FixedPoint.uq112x112(
                uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
            );
            price1Average = FixedPoint.uq112x112(
                uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
            );
        }

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    /// @notice Returns the amount of Morpho tokens according to the price average and the `_amountIn` of reward tokens.
    /// @param _amountIn The amount of reward tokens as input.
    /// @return The amount of Morpho tokens given the `_amountIn` as input.
    function consult(uint256 _amountIn) public view returns (uint256) {
        if (MORPHO == token0) return price1Average.mul(_amountIn).decode144();
        else return price0Average.mul(_amountIn).decode144();
    }
}
