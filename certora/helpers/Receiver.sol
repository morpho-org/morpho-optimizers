// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

contract Receiver {
    fallback() external payable {}

    function sendTo() external payable returns (bool) {
        return true;
    }

    receive() external payable {}
}
