// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IAToken} from "./aave/IAToken.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

interface IMatchingEngineForAave {
    function matchSuppliers(
        IAToken,
        ERC20,
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
        ERC20,
        uint256,
        uint256
    ) external returns (uint256);

    function unmatchBorrowers(
        address,
        uint256,
        uint256
    ) external returns (uint256);

    function updateBorrowers(address _poolTokenAddress, address _user) external;

    function updateSuppliers(address _poolTokenAddress, address _user) external;
}
