// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IComptroller} from "../munged/compound/interfaces/compound/ICompound.sol";

// TODO: symbolic behavior

contract SymbolicComptroller is IComptroller {

    // by creating a field for each function, then the function calls will always return the same value
    // Through mappings we can have the same parameters return the same values
    address internal _oracle;

    struct marketsStruct {
        bool b1;
        uint256 val;
        bool b2;
    }
    mapping(address => marketsStruct) public marketsRet;

    mapping(address => uint256[]) public enterMarketsRet;

    mapping(address => uint256[]) public exitMarketRet;

    function liquidationIncentiveMantissa() external override returns (uint256){
        uint256 ret;
        return ret;
    }

    function closeFactorMantissa() external override returns (uint256){
        uint256 ret;
        return ret;
    }

    function oracle() external override returns (address){
        return _oracle;
    }

    function markets(address token)
        external override
        returns (
            bool,
            uint256,
            bool
        )
    {
        return marketsRet[token];
    }

    function enterMarkets(address[] calldata cTokens) external override returns (uint256[] memory){
        return enterMarketsRet[cTokens[0]]; 
    }

    function exitMarket(address cToken) external override returns (uint256){
        return exitMarketRet[cToken];
    }

    // these nested mappings aren't very pretty, perhaps there is a better way to do this?
    mapping(address => mapping(address => mapping(uint256 => uint256))) public mintAllowedRet;

    function mintAllowed(
        address cToken,
        address minter,
        uint256 mintAmount
    ) external override returns (uint256){
        return mintAllowedRet[cToken][minter][mintAmount];
    }

    function mintVerify(
        address cToken,
        address minter,
        uint256 mintAmount,
        uint256 mintTokens
    ) external override {
        uint256 val = mintTokens; // chose an arbitrary parameter to reference, replace with functionality 
    }

    mapping(address => mapping(address => mapping(uint256 => uint256))) public redeemAllowedRet;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external override returns (uint256){
        return redeemAllowedRet[cToken][redeemer][redeemTokens];
    }

    function redeemVerify(
        address cToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external override {
        uint256 val = redeemAmount;
    }


    mapping(address => mapping(address => mapping(uint256 => uint256))) public borrowAllowedRet;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external override returns (uint256){
        return borrowAllowedRet[cToken][borrower][borrowAmount];
    }

    function borrowVerify(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external override {
        uint256 val = borrowAmount;
    }

    mapping(address => mapping(address => mapping(addres => mapping(uint256 => uint256))))

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external override returns (uint256){
        return repayBorrowAllowedRet[cToken][payer][borrower][repayAmount];
    }

    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external override {
        uint256 val = repayAmount;
    }

    // struct liquidateBorrowAllowedParams {
    //     address cTokenBorrowed;
    //     address cTokenCollateral;
    //     address liquidator;
    //     address borrower;
    //     uint256 repayAmount;
    // }
    // mapping(liquidateBorrowAllowedParams => uint256) public liquidateBorrowAllowedRet;

    // function liquidateBorrowAllowed(
    //     address cTokenBorrowed,
    //     address cTokenCollateral,
    //     address liquidator,
    //     address borrower,
    //     uint256 repayAmount
    // ) external override returns (uint256){
    //     return liquidateBorrowAllowedRet[liquidateBorrowAllowedParams(cTokenBorrowed, cTokenCollateral, liquidator, borrower, repayAmount)];
    // }

    // function liquidateBorrowVerify(
    //     address cTokenBorrowed,
    //     address cTokenCollateral,
    //     address liquidator,
    //     address borrower,
    //     uint256 repayAmount,
    //     uint256 seizeTokens
    // ) external override {
    //     uint256 val = seizeTokens;
    // }

    // struct seizeAllowedParams {
    //     address cTokenCollateral;
    //     address cTokenBorrowed;
    //     address liquidator;
    //     address borrower;
    //     uint256 seizeTokens;
    // }
    // mapping(seizeAllowedParams => uint256) public seizeAllowedRet;

    // function seizeAllowed(
    //     address cTokenCollateral,
    //     address cTokenBorrowed,
    //     address liquidator,
    //     address borrower,
    //     uint256 seizeTokens
    // ) external override returns (uint256){
    //     return seizeAllowedRet[seizeAllowedParams(cTokenCollateral, cTokenBorrowed, liquidator, borrower, seizeTokens)];
    // }

    // function seizeVerify(
    //     address cTokenCollateral,
    //     address cTokenBorrowed,
    //     address liquidator,
    //     address borrower,
    //     uint256 seizeTokens
    // ) external override
    // {
    //     uint256 val = seizeTokens;
    // }

    // struct transferAllowedParams{
    //     address cToken;
    //     address src;
    //     address dst;
    //     uint256 transferTokens;
    // }
    // mapping(transferAllowedParams => uint256) public transferAllowedRet;

    // function transferAllowed(
    //     address cToken,
    //     address src,
    //     address dst,
    //     uint256 transferTokens
    // ) external override returns (uint256)
    // {
    //     return transferAllowedRet[transferAllowedParams(cToken, src, dst, transferTokens)];
    // }

    // function transferVerify(
    //     address cToken,
    //     address src,
    //     address dst,
    //     uint256 transferTokens
    // ) external override {
    //     uint256 val = transferTokens;
    // }

    // /*** Liquidity/Liquidation Calculations ***/
    // struct LCSTParams{
    //     address cTokenBorrowed;
    //     address cTokenCollateral;
    //     uint256 repayAmount;
    // }

    // mapping(LCSTParams => uint256) public LCSTRetA;
    // mapping(LCSTParams => uint256) public LCSTRetB;

    // function liquidateCalculateSeizeTokens(
    //     address cTokenBorrowed,
    //     address cTokenCollateral,
    //     uint256 repayAmount
    // ) external override view returns (uint256, uint256) { 
    //     LCSTParams params = LCSTParams(cTokenBorrowed, cTokenCollateral, repayAmount);
    //     return(LCSTRetA[params], LCSTRetB[params]);
    // }


    // mapping(uint256 => uint256) public GALRetA;
    // mapping(uint256 => uint256) public GALRetB;
    // mapping(uint256 => uint256) public GALRetC;

    // function getAccountLiquidity(address account)
    //     external override
    //     view
    //     returns (
    //         uint256,
    //         uint256,
    //         uint256
    //     ) 
    //     {
    //         return (GALRetA[account], GALRetB[account], GALRetC[account]);
    //     }

    // struct GHALParams {
    //     address a1;
    //     address a2;
    //     uint256 v1;
    //     uint256 v2;
    // }
    // mapping(GHALParams => uint256) GHALRetA;
    // mapping(GHALParams => uint256) GHALRetB;
    // mapping(GHALParams => uint256) GHALRetC;

    // function getHypotheticalAccountLiquidity(
    //     address a1,
    //     address a2,
    //     uint256 v1,
    //     uint256 v2
    // )
    //     external override 
    //     returns (
    //         uint256,
    //         uint256,
    //         uint256
    //     )
    // {
    //     GHALParams params = GHALParams(a1, a2, v1, v2);
    //     return (GHALRetA[params], GHALRetB[params], GHALRetC[params]);
    // }

    // mapping(address => mapping(address => bool)) public checkMembershipRet;

    // function checkMembership(address, address) external override view returns (bool)
    //  {
    //      return checkMembershipRet[address][address];
    //  }
}