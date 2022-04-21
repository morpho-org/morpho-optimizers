// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ICToken} from "../interfaces/compound/ICompound.sol";
import "../interfaces/IMatchingEngine.sol";

import "@openzeppelin/contracts/utils/Address.sol";

library MatchingEngineDCs {
    using Address for address;

    function matchSuppliersDC(
        IMatchingEngine _matchingEngine,
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.matchSuppliers.selector,
                _poolToken,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchSuppliersDC(
        IMatchingEngine _matchingEngine,
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.unmatchSuppliers.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function matchBorrowersDC(
        IMatchingEngine _matchingEngine,
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.matchBorrowers.selector,
                _poolToken,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchBorrowersDC(
        IMatchingEngine _matchingEngine,
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.unmatchBorrowers.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function updateBorrowersDC(
        IMatchingEngine _matchingEngine,
        address _poolTokenAddress,
        address _user
    ) internal {
        address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.updateBorrowers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }

    function updateSuppliersDC(
        IMatchingEngine _matchingEngine,
        address _poolTokenAddress,
        address _user
    ) internal {
        address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.updateSuppliers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }
}
