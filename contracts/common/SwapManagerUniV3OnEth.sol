// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./libraries/uniswap/PoolAddress.sol";
import "./libraries/uniswap/FullMath.sol";
import "./libraries/uniswap/TickMath.sol";

/// @title SwapManagerUniV3OnEth.
/// @dev Smart contract managing the swap of reward token to Morpho token on Uniswap V3 on mainnet.
contract SwapManagerUniV3OnEth is ISwapManager {
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    /// Storage ///

    uint256 public constant THREE_PERCENT = 300; // 3% in basis points.
    uint32 public constant TWAP_INTERVAL = 3600; // 1 hour interval.
    uint256 public constant MAX_BASIS_POINTS = 10000; // 100% in basis points.

    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // The address of the Uniswap V3 factory.
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // The Uniswap V3 router.
    address public constant stkAAVE = 0x4da27a545c0c5B758a6BA100e3a049001de870f5; // The address of stkAAVE token.
    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // The address of AAVE token.
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // The address of WETH9 token.

    address public immutable MORPHO; // Morpho token address.
    uint24 public constant FIRST_POOL_FEE = 3000; // Fee on Uniswap for stkAAVE/AAVE pool.
    uint24 public constant SECOND_POOL_FEE = 3000; // Fee on Uniswap for AAVE/WETH9 pool.
    uint24 public immutable MORPHO_POOL_FEE; // Fee on Uniswap for WETH9/MORPHO pool.

    IUniswapV3Pool public pool0;
    IUniswapV3Pool public pool1;
    IUniswapV3Pool public pool2;

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

    /// @notice Constructs the SwapManagerUniV3 contract.
    /// @param _morphoToken The Morpho token address.
    /// @param _morphoPoolFee The reward token address.
    constructor(address _morphoToken, uint24 _morphoPoolFee) {
        MORPHO = _morphoToken;
        MORPHO_POOL_FEE = _morphoPoolFee;

        pool0 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(stkAAVE, AAVE, FIRST_POOL_FEE)
            )
        );
        pool1 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(AAVE, WETH9, SECOND_POOL_FEE)
            )
        );
        pool2 = IUniswapV3Pool(
            PoolAddress.computeAddress(
                FACTORY,
                PoolAddress.getPoolKey(WETH9, _morphoToken, _morphoPoolFee)
            )
        );
    }

    /// External ///

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

        (expectedAmountOutMinimum, path) = _getMultiplePathParams(_amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: _receiver,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: expectedAmountOutMinimum
        });

        // Execute the swap
        IERC20(stkAAVE).safeApprove(address(swapRouter), _amountIn);
        amountOut = swapRouter.exactInput(params);

        emit Swapped(_receiver, _amountIn, amountOut);
    }

    /// Internal ///

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

        uint256 priceX961;
        uint256 priceX962;

        {
            // pool0 is not observed as aave and stkaave are pegged
            // we consider 1 aave = 1 stkaave as the fair price
            (int56[] memory tickCumulatives1, ) = pool1.observe(secondsAgo);
            (int56[] memory tickCumulatives2, ) = pool2.observe(secondsAgo);

            // For the pair token0/token1 -> 1.0001 * readingTick = price = token1 / token0
            // So token1 = price * token0

            uint160 sqrtPriceX961 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives1[1] - tickCumulatives1[0]) / int24(uint24(TWAP_INTERVAL)))
            );
            uint160 sqrtPriceX962 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives2[1] - tickCumulatives2[0]) / int24(uint24(TWAP_INTERVAL)))
            );
            priceX961 = _getPriceX96FromSqrtPriceX96(sqrtPriceX961);
            priceX962 = _getPriceX96FromSqrtPriceX96(sqrtPriceX962);
        }

        // stkAAVE/AAVE -> token0 = stkAAVE
        // AAVE/WETH9 -> token0 = AAVE

        // Computation depends on the position of token in pool
        if (pool2.token0() == WETH9) {
            expectedAmountOutMinimum = _amountIn.mulDiv(priceX961, FixedPoint96.Q96).mulDiv(
                priceX962,
                FixedPoint96.Q96
            );
        } else {
            expectedAmountOutMinimum = _amountIn.mulDiv(priceX961, FixedPoint96.Q96).mulDiv(
                FixedPoint96.Q96,
                priceX962
            );
        }

        // Max slippage of 3% for the trade
        expectedAmountOutMinimum = expectedAmountOutMinimum.mulDiv(
            MAX_BASIS_POINTS - THREE_PERCENT,
            MAX_BASIS_POINTS
        );
        path = abi.encodePacked(
            stkAAVE,
            FIRST_POOL_FEE,
            AAVE,
            SECOND_POOL_FEE,
            WETH9,
            MORPHO_POOL_FEE,
            MORPHO
        );
    }

    /// @dev Returns the price in fixed point 96 from the square of the price in fixed point 96.
    /// @param _sqrtPriceX96 The square of the price in fixed point 96.
    /// @return priceX96 The price in fixed point 96.
    function _getPriceX96FromSqrtPriceX96(uint160 _sqrtPriceX96)
        public
        pure
        returns (uint256 priceX96)
    {
        return FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, FixedPoint96.Q96);
    }
}
