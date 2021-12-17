// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

library PUErrors {
    string public constant PU_UPDATE_BORROWER_POSITIONS_FAIL = "0";
    string public constant PU_UPDATE_SUPPLIER_POSITIONS_FAIL = "1";
    string public constant PU_GET_BORROWER_ACCOUNT_ON_POOL = "2";
    string public constant PU_GET_BORROWER_ACCOUNT_IN_P2P = "3";
    string public constant PU_GET_SUPPLIER_ACCOUNT_ON_POOL = "4";
    string public constant PU_GET_SUPPLIER_ACCOUNT_IN_P2P = "5";
}
