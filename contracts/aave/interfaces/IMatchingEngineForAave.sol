// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAToken} from "./aave/IAToken.sol";

import "../PositionsManagerForAave.sol";

interface IMatchingEngineForAave {
    function matchSuppliers(
        IAToken,
        IERC20,
        uint256
    ) external returns (uint256);

    function unmatchSuppliers(address, uint256) external;

    function matchBorrowers(
        IAToken,
        IERC20,
        uint256
    ) external returns (uint256);

    function unmatchBorrowers(address, uint256) external;

    function updateBorrowers(address, address) external;

    function updateSuppliers(address, address) external;

    function getHead(address, uint8) external returns (address);

    function getNext(
        address,
        uint8,
        address
    ) external returns (address);
}
