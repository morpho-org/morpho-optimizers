// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IAToken} from "../interfaces/aave/IAToken.sol";
import "../interfaces/IMatchingEngineForAave.sol";

import "@openzeppelin/contracts/utils/Address.sol";

library MatchingEngineFns {
    using Address for address;

    function matchSuppliersDC(
        IMatchingEngineForAave _matchingEngine,
        IAToken _poolToken,
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.matchSuppliers.selector,
                _poolToken,
                _underlyingToken,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchSuppliersDC(
        IMatchingEngineForAave _matchingEngine,
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
        IMatchingEngineForAave _matchingEngine,
        IAToken _poolToken,
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        bytes memory data = address(_matchingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _matchingEngine.matchBorrowers.selector,
                _poolToken,
                _underlyingToken,
                _amount,
                _maxGasToConsume
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchBorrowersDC(
        IMatchingEngineForAave _matchingEngine,
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
        IMatchingEngineForAave _matchingEngine,
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
        IMatchingEngineForAave _matchingEngine,
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
