// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/compound/interfaces/dependencies/@openzeppelin/IContext.sol";

interface IOwnable is IContext {
    function owner() external returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;
}
