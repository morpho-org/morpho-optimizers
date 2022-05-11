// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./SymbolicInterestRateModel.sol";
import "./SymbolicComptroller.sol";

contract SymbolicCToken {
    bool public isCTokenRet;

    function isCToken() external returns (bool) {
        return isCTokenRet;
    }

    mapping(address => mapping(uint256 => bool)) public transferRet;

    function transfer(address dst, uint256 amount) external returns (bool) {
        return transferRet[dst][amount];
    }

    mapping(address => mapping(address => mapping(uint256 => bool))) public transferFromRet;

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool) {
        return transferFromRet[src][dst][amount];
    }

    mapping(address => mapping(uint256 => bool)) public approveRet;

    function approve(address spender, uint256 amount) external returns (bool) {
        approveRet[spender][amount];
    }

    mapping(address => mapping(address => uint256)) public allowanceRet;

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowanceRet[owner][spender];
    }

    mapping(address => uint256) public balanceOfRet;

    function balanceOf(address owner) external view returns (uint256) {
        return balanceOfRet[owner];
    }

    mapping(address => uint256) public balanceOfUnderlyingRet;

    function balanceOfUnderlying(address owner) external returns (uint256) {
        return balanceOfUnderlyingRet[owner];
    }

    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    uint256 public borrowRatePerBlockRet;

    function borrowRatePerBlock() external view returns (uint256) {
        return borrowRatePerBlockRet;
    }

    uint256 public supplyRatePerBlockRet;

    function supplyRatePerBlock() external view returns (uint256) {
        return supplyRatePerBlockRet;
    }

    uint256 public totalBorrowsCurrentRet;

    function totalBorrowsCurrent() external returns (uint256) {
        return totalBorrowsCurrentRet;
    }

    mapping(address => uint256) public borrowBalanceCurrentRet;

    function borrowBalanceCurrent(address account) external returns (uint256) {
        totalBorrowsCurrentRet[account];
    }

    mapping(address => uint256) public borrowBalanceStoredRet;

    function borrowBalanceStored(address account) external view returns (uint256) {
        borrowBalanceStoredRet[account];
    }

    uint256 public exchangeRateCurrentRet;

    function exchangeRateCurrent() external returns (uint256) {
        return exchangeRateCurrentRet;
    }

    uint256 public exchangeRateStoredRet;

    function exchangeRateStored() external view returns (uint256) {
        return exchangeRateStoredRet;
    }

    uint256 public getCashRet;

    function getCash() external view returns (uint256) {
        return getCashRet;
    }

    mapping(address => mapping(address => mapping(uint256 => uint256))) public seizeRet;

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256) {
        return seizeRet[liquidator][borrower][seizeTokens];
    }

    uint256 public borrowRateRet;

    function borrowRate() external returns (uint256) {
        return borrowRateRet;
    }

    uint256 public borrowIndexRet;

    function borrowIndex() external view returns (uint256) {
        return borrowIndexRet;
    }

    uint256 public borrowRet;

    function borrow(uint256) external returns (uint256) {
        return borrowRet;
    }

    uint256 public repayBorrowRet;

    function repayBorrow(uint256) external returns (uint256) {
        return repayBorrowRet;
    }

    mapping(address => mapping(uint256 => uint256)) public repayBorrowBehalfRet;

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256) {
        return repayBorrowBehalfRet[borrower][repayAmount];
    }

    address public underlyingRet;

    function underlying() external view returns (address) {
        return underlyingRet;
    }

    mapping(uint256 => address) public mintRet;

    function mint(uint256) external returns (uint256) {
        return mintRet;
    }

    mapping(uint256 => address) public redeemUnderlyingRet;

    function redeemUnderlying(uint256 a) external returns (uint256) {
        return redeemUnderlyingRet[a];
    }

    uint256 public accrueInterest;

    uint256 public totalSupply;

    uint256 public totalBorrows;

    uint256 public accrualBlockNumber;

    uint256 public totalReserves;

    SymbolicInterestRateModel public interestRateModel;

    uint256 public reserveFactorMantissa;

    uint256 public initialExchangeRateMantissa;

    /*** Admin Functions ***/

    mapping(address => uint256) public _setPendingAdminRet;

    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint256) {
        return _setPendingAdmin[newPendingAdmin];
    }

    uint256 public _acceptAdminRet;

    function _acceptAdmin() external returns (uint256) {
        return _acceptAdminRet;
    }

    mapping(SymbolicComptroller => uint256) public _setComptrollerRep;

    function _setComptroller(SymbonlicComptroller newComptroller) external returns (uint256) {
        return _setComptrollerRep[newComptroller];
    }

    mapping(uint256 => uint256) public _setReserveFactorRep;

    function _setReserveFactor(uint256 newReserveFactorMantissa) external returns (uint256) {
        return _setReserveFactor[newReserveFactorMantissa];
    }

    mapping(uint256 => uint256) public _reduceReservesRep;

    function _reduceReserves(uint256 reduceAmount) external returns (uint256) {
        return _reduceReservesRep[reduceAmount];
    }

    mapping(SymbolicInterestRateModel => uint256) public _setInterestRateModelRep;

    function _setInterestRateModel(SymbolicInterestRateModel newInterestRateModel)
        external
        returns (uint256)
    {
        return _setInterestRateModelRep[newInterestRateModel];
    }
}
