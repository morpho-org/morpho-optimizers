// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;
import {ICompoundOracle} from "../munged/compound/interfaces/compound/ICompound.sol";

contract SymbolicOracle is ICompoundOracle {

    mapping(address => uint256) _underlyingPrice;

    function getUnderlyingPrice(address token) external override view returns (uint256) {
        return _underlyingPrice[token];
    }

    function setUnderlyingPrice(address token, uint256 price) public {
        _underlyingPrice[token] = price;
    }
}
