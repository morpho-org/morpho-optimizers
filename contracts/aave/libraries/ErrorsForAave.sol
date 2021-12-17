// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

library Errors {
    string public constant MM_MARKET_NOT_CREATED = "0";
    string public constant MM_MARKET_ALREADY_CREATED = "1";
    string public constant MM_MARKET_CREATED_FAIL_ON_COMP = "2";
    string public constant PM_MARKET_NOT_CREATED = "3";
    string public constant PM_AMOUNT_NOT_ABOVE_THRESHOLD = "4";
    string public constant PM_ONLY_MARKETS_MANAGER = "5";
    string public constant PM_AMOUNT_IS_0 = "6";
    string public constant PM_DEBT_VALUE_NOT_ABOVE_MAX = "7";
    string public constant PM_AMOUNT_ABOVE_ALLOWED_TO_REPAY = "8";
    string public constant PM_TO_SEIZE_ABOVE_COLLATERAL = "9";
    string public constant PM_REMAINING_TO_MATCH_IS_NOT_0 = "10";
    string public constant PM_REMAINING_TO_UNMATCH_IS_NOT_0 = "11";
    string public constant PM_DEBT_VALUE_ABOVE_MAX = "12";
    string public constant PM_SUPPLY_ABOVE_CAP_VALUE = "13";
    string public constant PM_COULD_NOT_UNMATCH_FULL_AMOUNT = "14";
}
