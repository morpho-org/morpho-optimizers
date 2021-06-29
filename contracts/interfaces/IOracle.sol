pragma solidity ^0.8.0;

interface IOracle {
	function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut);
}
