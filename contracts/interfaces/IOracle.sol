pragma solidity ^0.8.0;

interface IOracle {
    function consult() external view returns (uint256);
}
