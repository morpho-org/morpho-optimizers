// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ISwapManager.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./libraries/uniswap/PoolAddress.sol";

interface Weth9Provider {
    function WETH9() external view returns (address);
}

/// @title SwapManager for Uniswap V3.
/// @notice Smart contract managing the swap of reward tokens to Morpho tokens on Uniswap V3.
contract SwapManagerUniV3 is ISwapManager {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    /// STORAGE ///

    uint256 public constant ONE_PERCENT = 100; // 1% in basis points.
    uint256 public constant TWO_PERCENT = 200; // 2% in basis points.
    uint32 public constant TWAP_INTERVAL = 1 hours; // 1 hour interval.
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.

    // Hard coded addresses as they are the same accross chains.
    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // The address of the Uniswap V3 factory.
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // The Uniswap V3 router.

    address public WETH9; // Intermediate token address.
    address public immutable REWARD_TOKEN; // The reward token address.
    address public immutable MORPHO; // The Morpho token address.
    uint24 public immutable REWARD_POOL_FEE; // Fee on Uniswap for REWARD_TOKEN/WETH9 pool.
    uint24 public immutable MORPHO_POOL_FEE; // Fee on Uniswap for MORPHO/WETH9 pool.

    IUniswapV3Pool public pool0;
    IUniswapV3Pool public pool1;
    bool public singlePath;

    /// EVENTS ///

    /// @notice Emitted when a swap to Morpho tokens happens.
    /// @param _receiver The address of the receiver.
    /// @param _amountIn The amount of reward token swapped.
    /// @param _amountOut The amount of Morpho token received.
    event Swapped(address _receiver, uint256 _amountIn, uint256 _amountOut);

    /// CONSTRUCTOR ///

    /// @notice Constructs the SwapManagerUniV3 contract.
    /// @param _morphoToken The Morpho token address.
    /// @param _morphoPoolFee The fee on Uniswap for REWARD_TOKEN/WETH9 pool.
    /// @param _rewardToken The reward token address.
    /// @param _rewardPoolFee The fee on Uniswap for MORPHO/WETH9 pool.
    constructor(
        address _morphoToken,
        uint24 _morphoPoolFee,
        address _rewardToken,
        uint24 _rewardPoolFee
    ) {
        MORPHO = _morphoToken;
        MORPHO_POOL_FEE = _morphoPoolFee;
        REWARD_TOKEN = _rewardToken;
        REWARD_POOL_FEE = _rewardPoolFee;
        WETH9 = Weth9Provider(address(swapRouter)).WETH9();

        singlePath = _rewardToken == WETH9;
        if (!singlePath) {
            pool0 = IUniswapV3Pool(
                PoolAddress.computeAddress(
                    FACTORY,
                    PoolAddress.getPoolKey(_rewardToken, WETH9, _rewardPoolFee)
                )
            );
        }
        pool1 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(WETH9, _morphoToken, _morphoPoolFee)
            )
        );
    }

    /// EXTERNAL ///

    /// @notice Swaps reward tokens to Morpho token.
    /// @param _amountIn The amount of reward token to swap.
    /// @param _receiver The address of the receiver of the Morpho tokens.
    /// @return amountOut The amount of Morpho tokens sent.
    function swapToMorphoToken(uint256 _amountIn, address _receiver)
        external
        override
        returns (uint256 amountOut)
    {
        uint256 expectedAmountOutMinimum;
        bytes memory path;

        if (singlePath) (expectedAmountOutMinimum, path) = _getSinglePathParams(_amountIn);
        else (expectedAmountOutMinimum, path) = _getMultiplePathParams(_amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: _receiver,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: expectedAmountOutMinimum
        });

        // Execute the swap
        ERC20(REWARD_TOKEN).safeApprove(address(swapRouter), _amountIn);
        amountOut = swapRouter.exactInput(params);

        emit Swapped(_receiver, _amountIn, amountOut);
    }

    /// INTERNAL ///

    /// @dev Returns the minimum expected amount of Morpho token to receive and the multiple path for a swap.
    /// @param _amountIn The amount of reward token to swap.
    /// @return expectedAmountOutMinimum The minimum amount of Morpho tokens to receive.
    /// @return path The path for the swap.
    function _getMultiplePathParams(uint256 _amountIn)
        internal
        view
        returns (uint256 expectedAmountOutMinimum, bytes memory path)
    {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = TWAP_INTERVAL;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives0, ) = pool0.observe(secondsAgo);
        (int56[] memory tickCumulatives1, ) = pool1.observe(secondsAgo);

        // For the pair token0/token1 -> 1.0001 * readingTick = price = token1 / token0
        // So token1 = price * token0

        // Ticks (imprecise as it's an integer) to price.
        uint160 sqrtPriceX960 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives0[1] - tickCumulatives0[0]) / int24(uint24(TWAP_INTERVAL)))
        );
        uint160 sqrtPriceX961 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives1[1] - tickCumulatives1[0]) / int24(uint24(TWAP_INTERVAL)))
        );

        uint256 priceX960 = _getPriceX96FromSqrtPriceX96(sqrtPriceX960);
        uint256 priceX961 = _getPriceX96FromSqrtPriceX96(sqrtPriceX961);

        // Computation depends on the position of token in pools.
        if (REWARD_TOKEN == pool0.token0() && WETH9 == pool1.token0()) {
            expectedAmountOutMinimum = _amountIn.mulDiv(priceX960, FixedPoint96.Q96).mulDiv(
                priceX961,
                FixedPoint96.Q96
            );
        } else if (REWARD_TOKEN == pool0.token1() && WETH9 == pool1.token0()) {
            expectedAmountOutMinimum = _amountIn.mulDiv(FixedPoint96.Q96, priceX960).mulDiv(
                priceX961,
                FixedPoint96.Q96
            );
        } else if (REWARD_TOKEN == pool0.token0() && WETH9 == pool1.token1()) {
            expectedAmountOutMinimum = _amountIn.mulDiv(FixedPoint96.Q96, priceX961).mulDiv(
                priceX960,
                FixedPoint96.Q96
            );
        } else {
            expectedAmountOutMinimum = _amountIn.mulDiv(FixedPoint96.Q96, priceX960).mulDiv(
                FixedPoint96.Q96,
                priceX961
            );
        }

        // Max slippage of 2% for the trade
        expectedAmountOutMinimum = expectedAmountOutMinimum.mulDiv(
            MAX_BASIS_POINTS - TWO_PERCENT,
            MAX_BASIS_POINTS
        );
        path = abi.encodePacked(REWARD_TOKEN, REWARD_POOL_FEE, WETH9, MORPHO_POOL_FEE, MORPHO);
    }

    function _getSinglePathParams(uint256 _amountIn)
        internal
        view
        returns (uint256 expectedAmountOutMinimum, bytes memory path)
    {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = TWAP_INTERVAL;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives1, ) = pool1.observe(secondsAgo);

        // For the pair token0/token1 -> 1.0001 * readingTick = price = token1 / token0
        // So token1 = price * token0

        // Ticks (imprecise as it's an integer) to price.
        uint160 sqrtPriceX961 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives1[1] - tickCumulatives1[0]) / int24(uint24(TWAP_INTERVAL)))
        );

        // Computation depends on the position of token in pool.
        if (pool1.token0() == REWARD_TOKEN) {
            expectedAmountOutMinimum = _amountIn.mulDiv(
                _getPriceX96FromSqrtPriceX96(sqrtPriceX961),
                FixedPoint96.Q96
            );
        } else {
            expectedAmountOutMinimum = _amountIn.mulDiv(
                FixedPoint96.Q96,
                _getPriceX96FromSqrtPriceX96(sqrtPriceX961)
            );
        }

        // Max slippage of 1% for the trade.
        expectedAmountOutMinimum =
            (expectedAmountOutMinimum * (MAX_BASIS_POINTS - ONE_PERCENT)) /
            MAX_BASIS_POINTS;
        path = abi.encodePacked(REWARD_TOKEN, MORPHO_POOL_FEE, MORPHO);
    }

    /// @dev Returns the price in fixed point 96 from the square of the price in fixed point 96.
    /// @param _sqrtPriceX96 The square of the price in fixed point 96.
    /// @return priceX96 The price in fixed point 96.
    function _getPriceX96FromSqrtPriceX96(uint160 _sqrtPriceX96)
        internal
        pure
        returns (uint256 priceX96)
    {
        return FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, FixedPoint96.Q96);
    }
}
