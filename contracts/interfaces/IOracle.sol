pragma solidity 0.8.6;

interface IOracle {
    function consult() external view returns (uint256);
}
