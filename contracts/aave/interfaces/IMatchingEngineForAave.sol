// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./aave/IAToken.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMatchingEngineForAave {
    function matchSuppliers(
        IAToken,
        IERC20,
        uint256,
        uint256
    ) external returns (uint256);

    function unmatchSuppliers(
        address,
        uint256,
        uint256
    ) external returns (uint256);

    function matchBorrowers(
        IAToken,
        IERC20,
        uint256,
        uint256
    ) external returns (uint256);

    function unmatchBorrowers(
        address,
        uint256,
        uint256
    ) external;

    function updateBorrowers(address _poolTokenAddress, address _user) external;

    function updateSuppliers(address _poolTokenAddress, address _user) external;
}
