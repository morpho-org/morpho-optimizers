pragma solidity >=0.6.6;

interface IOracle {
    function consult() external view returns (uint256);
}
