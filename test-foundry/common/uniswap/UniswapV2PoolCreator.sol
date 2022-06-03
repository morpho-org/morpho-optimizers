pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract UniswapV2PoolCreator {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public swapRouter =
        IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4); // JoeRouter.
    address public constant WETH9 = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7; // Intermediate token address.

    // Destabilize the pool to make sire the swap manager is working fine.
    uint256 public amount0ToMint = 0.001 ether;
    uint256 public amount1ToMint = 10 ether;

    function createPoolAndAddLiquidity(address _token0)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 liquidity
        )
    {
        TransferHelper.safeApprove(_token0, address(swapRouter), amount0ToMint);
        TransferHelper.safeApprove(WETH9, address(swapRouter), amount1ToMint);

        (amount0, amount1, liquidity) = swapRouter.addLiquidity(
            _token0,
            WETH9,
            amount0ToMint,
            amount1ToMint,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(_token0, address(swapRouter), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(_token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(WETH9, address(swapRouter), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(WETH9, msg.sender, refund1);
        }
    }

    function swap(address _morphoToken, uint256 _amount) external {
        address[] memory path = new address[](2);
        path[0] = WETH9;
        path[1] = _morphoToken;

        // Execute the swap
        IERC20(WETH9).safeApprove(address(swapRouter), _amount);
        swapRouter.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp);
    }
}
