// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "../interfaces/IMatchingEngineManager.sol";

import "@openzeppelin/contracts/utils/Address.sol";

/// @title DataLogic
/// @notice Implement the base logic for data structure specific functions.
library DataLogic {
    using Address for address;

    /// @dev Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the borrower to move.
    function updateBorrowers(
        address _poolTokenAddress,
        address _user,
        IMatchingEngineManager _matchingEngineManager
    ) external {
        address(_matchingEngineManager).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngineManager.updateBorrowers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }

    /// @dev Updates suppliers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the supplier to move.
    function updateSuppliers(
        address _poolTokenAddress,
        address _user,
        IMatchingEngineManager _matchingEngineManager
    ) external {
        address(_matchingEngineManager).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngineManager.updateSuppliers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }
}
