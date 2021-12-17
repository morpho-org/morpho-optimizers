// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

library Errors {
    string public constant MM_MARKET_NOT_CREATED = "0";
    string public constant MM_POSITIONS_MANAGER_SET = "1";
    string public constant MM_MARKET_ALREADY_CREATED = "2";
    string public constant MM_MARKET_CREATED_FAIL_ON_COMP = "3";
    string public constant PM_MARKET_NOT_CREATED = "4";
    string public constant PM_AMOUNT_NOT_ABOVE_THRESHOLD = "5";
    string public constant PM_ONLY_MARKETS_MANAGER = "6";
    string public constant PM_AMOUNT_IS_0 = "7";
    string public constant PM_DEBT_VALUE_NOT_ABOVE_MAX = "8";
    string public constant PM_AMOUNT_ABOVE_ALLOWED_TO_REPAY = "9";
    string public constant PM_TO_SEIZE_ABOVE_COLLATERAL = "10";
    string public constant PM_COULD_NOT_MATCH_FULL_AMOUNT = "11";
    string public constant PM_COULD_NOT_UNMATCH_FULL_AMOUNT = "12";
    string public constant PM_DEBT_VALUE_ABOVE_MAX = "13";
    string public constant PM_DELEGATECALL_BORROWER_UPDATE_NOT_SUCCESS = "14";
    string public constant PM_DELEGATECALL_SUPPLIER_UPDATE_NOT_SUCCESS = "15";
    string public constant PM_SUPPLY_ABOVE_CAP_VALUE = "16";
}
