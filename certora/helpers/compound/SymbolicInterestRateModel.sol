// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

contract SymbolicInterestRateModel {
    bool public constant isInterestRateModel = true;

    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) public getBorrowRateRet;

    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256) {
        return getBorrowRateRet[cash][borrows][reserves];
    }

    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))))
        public getSupplyRateRet;

    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256) {
        return getSupplyRateRet[cash][borrows][reserves][reserveFactorMantissa];
    }
}
