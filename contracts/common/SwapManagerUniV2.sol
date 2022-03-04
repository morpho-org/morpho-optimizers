// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwapManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SwapManager for Uniswap V2.
/// @dev Smart contract managing the swap of reward token to Morpho token.
contract SwapManagerUniV2 is ISwapManager {
    using SafeERC20 for IERC20;

    /// Storage ///

    uint256 public constant ONE_PERCENT = 100; // 1% in basis points.
    uint256 public constant MAX_BASIS_POINTS = 10000; // 100% in basis points.

    IUniswapV2Router02 public swapRouter =
        IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4); // JoeRouter

    address public immutable REWARD_TOKEN; // The reward token address.
    address public immutable MORPHO; // Morpho token address.

    IUniswapV2Pair public pair;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public blockTimestampLast;
    uint256 public price0Average;
    uint256 public price1Average;

    /// Events ///

    /// @notice Emitted when a swap to Morpho tokens happens.
    /// @param _receiver The address of the receiver.
    /// @param _amountIn The amount of reward token swapped.
    /// @param _amountOut The amount of Morpho token received.
    event Swapped(address _receiver, uint256 _amountIn, uint256 _amountOut);

    /// Constructor ///

    /// @notice Constructs the SwapManager contract.
    /// @param _morphoToken The Morpho token address.
    /// @param _rewardToken The reward token address.
    constructor(address _morphoToken, address _rewardToken) {
        MORPHO = _morphoToken;
        REWARD_TOKEN = _rewardToken;

        pair = IUniswapV2Pair(
            IUniswapV2Factory(swapRouter.factory()).getPair(_morphoToken, _rewardToken)
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
        (uint256 reserve0, uint256 reserve1, uint256 blockTimestampReserve) = pair.getReserves();
        uint256 price0Cumulative = pair.price0CumulativeLast();
        if (price0Cumulative == 0) {
            // No swap yet
            price0CumulativeLast = reserve1 / reserve0;
            price1CumulativeLast = reserve0 / reserve1;

            price0Average = price0CumulativeLast;
            price1Average = price1CumulativeLast;
        } else {
            uint256 timeElapsed = block.timestamp - blockTimestampReserve;
            if (timeElapsed > 0) {
                uint256 price1Cumulative = pair.price1CumulativeLast();
                price0Average = (price0Cumulative - price0CumulativeLast) / timeElapsed;
                price1Average = (price1Cumulative - price1CumulativeLast) / timeElapsed;

                price0CumulativeLast = price0Cumulative;
                price1CumulativeLast = price1Cumulative;
                blockTimestampLast = block.timestamp;
            }
        }

        if (MORPHO == pair.token0()) {
            amountOut = (price1Average * _amountIn) / price0Average;
        } else {
            amountOut = (price0Average * _amountIn) / price1Average;
        }

        // Max slippage of 1% for the trade
        uint256 expectedAmountOutMinimum = (amountOut * (MAX_BASIS_POINTS - ONE_PERCENT)) /
            MAX_BASIS_POINTS;

        address[] memory path = new address[](2);
        path[0] = REWARD_TOKEN;
        path[1] = MORPHO;

        // Execute the swap
        IERC20(REWARD_TOKEN).safeApprove(address(swapRouter), _amountIn);
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
}
