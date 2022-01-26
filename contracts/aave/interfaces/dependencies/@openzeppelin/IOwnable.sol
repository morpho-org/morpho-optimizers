// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IContext.sol";

interface IOwnable is IContext {
    function owner() external returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;
}
