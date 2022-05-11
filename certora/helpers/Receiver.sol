// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

contract Receiver {
    fallback() external payable {}

    function sendTo() external payable returns (bool) {
        return true;
    }

    receive() external payable {}
}
