// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ISwapManager.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./libraries/uniswap/PoolAddress.sol";
import "./libraries/uniswap/FullMath.sol";
import "./libraries/uniswap/TickMath.sol";

/// @title SwapManager.
/// @dev Smart contract managing the swap of reward token to Morpho token.
contract SwapManager is ISwapManager {
    using SafeTransferLib for ERC20;

    /// Storage ///

    uint24 public constant POOL_FEE = 3000; // Fee on Uniswap.
    uint256 public constant ONE_PERCENT = 100; // 1% in basis points.
    uint256 public constant MAX_BASIS_POINTS = 10000; // 100% in basis points.
    uint32 public constant TWAP_INTERVAL = 3600; // 1 hour interval.

    // Hard coded addresses as they are the same accross chains
    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // The address of the Uniswap V3 factory.
    address public constant WETH9 = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // Intermediate token address.
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public immutable REWARD_TOKEN; // The reward token address.
    address public immutable MORPHO; // Morpho token address.

    IUniswapV3Pool public pool0;
    IUniswapV3Pool public pool1;

    struct SwapVars {
        uint160 sqrtPriceX960;
        uint160 sqrtPriceX961;
        uint256 priceX960;
        uint256 priceX961;
        uint256 numerator;
        uint256 denominator;
        uint256 expectedAmountOutMinimum;
        int56[] tickCumulatives0;
        int56[] tickCumulatives1;
    }

    /// Events ///

    /// @notice Emitted when a swap to Morpho tokens happens.
    /// @param _receiver The address of the receiver.
    /// @param _amountIn The amount of reward token swapped.
    /// @param _amountOut The amount of Morpho token received.
    event Swapped(address _receiver, uint256 _amountIn, uint256 _amountOut);

    /// Structs ///

    // Struct to avoid stack too deep error
    struct OracleTwapVars {
        uint256 priceX960;
        uint256 priceX961;
        uint256 numerator;
        uint256 denominator;
        uint256 expectedAmountOutMinimum;
    }

    /// Constructor ///

    /// @notice Constructs the SwapManager contract.
    /// @param _morphoToken The Morpho token address.
    /// @param _rewardToken The reward token address.
    constructor(address _morphoToken, address _rewardToken) {
        MORPHO = _morphoToken;
        REWARD_TOKEN = _rewardToken;
        pool0 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(_rewardToken, WETH9, POOL_FEE)
            )
        );
        pool1 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(WETH9, _morphoToken, POOL_FEE)
            )
        );
    }

    /// External ///

    /// @dev Swaps reward tokens to Morpho token.
    /// @param _amountIn The amount of reward token to swap.
    /// @param _receiver The address of the receiver of the Morpho tokens.
    /// @return amountOut The amount of Morpho tokens sent.
    function swapToMorphoToken(uint256 _amountIn, address _receiver)
        external
        override
        returns (uint256 amountOut)
    {
        SwapVars memory vars;

        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = TWAP_INTERVAL;
        secondsAgo[1] = 0;

        (vars.tickCumulatives0, ) = pool0.observe(secondsAgo);
        (vars.tickCumulatives1, ) = pool1.observe(secondsAgo);

        // For the pair token0/token1 -> 1.0001 * readingTick = price = token1 / token0
        // So token1 = price * token0

        // Ticks (imprecise as it's an integer) to price
        vars.sqrtPriceX960 = TickMath.getSqrtRatioAtTick(
            int24(
                (vars.tickCumulatives0[1] - vars.tickCumulatives0[0]) / int24(uint24(TWAP_INTERVAL))
            )
        );
        vars.sqrtPriceX961 = TickMath.getSqrtRatioAtTick(
            int24(
                (vars.tickCumulatives1[1] - vars.tickCumulatives1[0]) / int24(uint24(TWAP_INTERVAL))
            )
        );
        vars.priceX960 = getPriceX96FromSqrtPriceX96(vars.sqrtPriceX960);
        vars.priceX961 = getPriceX96FromSqrtPriceX96(vars.sqrtPriceX961);

        // Computation depends on the position of token in pools
        if (REWARD_TOKEN == pool0.token0() && WETH9 == pool1.token0()) {
            vars.numerator = vars.priceX960 * vars.priceX961 * _amountIn;
            vars.denominator = 2**96 * 2**96;
        } else if (REWARD_TOKEN == pool0.token1() && WETH9 == pool1.token0()) {
            vars.numerator = 2**96 * vars.priceX961 * _amountIn;
            vars.denominator = vars.priceX960 * 2**96;
        } else if (REWARD_TOKEN == pool0.token0() && WETH9 == pool1.token1()) {
            vars.numerator = 2**96 * vars.priceX960 * _amountIn;
            vars.denominator = vars.priceX961 * 2**96;
        } else {
            vars.numerator = 2**96 * 2**96 * _amountIn;
            vars.denominator = vars.priceX960 * vars.priceX961;
        }

        // Max slippage of 1% for the trade
        vars.expectedAmountOutMinimum =
            (vars.numerator * (MAX_BASIS_POINTS - ONE_PERCENT)) /
            (vars.denominator * MAX_BASIS_POINTS);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(REWARD_TOKEN, POOL_FEE, WETH9, POOL_FEE, MORPHO),
            recipient: _receiver,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: vars.expectedAmountOutMinimum
        });

        // Execute the swap
        ERC20(REWARD_TOKEN).safeApprove(address(swapRouter), _amountIn);
        amountOut = swapRouter.exactInput(params);

        emit Swapped(_receiver, _amountIn, amountOut);
    }

    /// public ///

    /// @dev Returns the price in fixed point 96 from the square of the price in fixed point 96.
    /// @param _sqrtPriceX96 The square of the price in fixed point 96.
    /// @return priceX96 The price in fixed point 96.
    function getPriceX96FromSqrtPriceX96(uint160 _sqrtPriceX96)
        public
        pure
        returns (uint256 priceX96)
    {
        return FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, FixedPoint96.Q96);
    }
}
