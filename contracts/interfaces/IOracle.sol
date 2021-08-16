pragma solidity 0.8.7;

interface IOracle {
    function consult() external view returns (uint256);
}
