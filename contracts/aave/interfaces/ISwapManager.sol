// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface ISwapManager {
    function swapToMorphoToken(
        address _tokenIn,
        uint256 _amountIn,
        address _receiver
    ) external returns (uint256 amountOut);
}
