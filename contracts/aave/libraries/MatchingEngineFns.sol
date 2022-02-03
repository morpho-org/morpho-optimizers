// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "../interfaces/aave/IAToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMatchingEngineForAave.sol";

import "@openzeppelin/contracts/utils/Address.sol";

library MatchingEngineFns {
    using Address for address;

    function matchSuppliersDC(
        IMatchingEngineForAave _mathingEngine,
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256) {
        bytes memory data = address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.matchSuppliers.selector,
                _poolToken,
                _underlyingToken,
                _amount
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchSuppliersDC(
        IMatchingEngineForAave _mathingEngine,
        address _poolTokenAddress,
        uint256 _amount
    ) internal {
        address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.unmatchSuppliers.selector,
                _poolTokenAddress,
                _amount
            )
        );
    }

    function matchBorrowersDC(
        IMatchingEngineForAave _mathingEngine,
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal returns (uint256) {
        bytes memory data = address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.matchBorrowers.selector,
                _poolToken,
                _underlyingToken,
                _amount
            )
        );
        return abi.decode(data, (uint256));
    }

    function unmatchBorrowersDC(
        IMatchingEngineForAave _mathingEngine,
        address _poolTokenAddress,
        uint256 _amount
    ) internal {
        address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.unmatchBorrowers.selector,
                _poolTokenAddress,
                _amount
            )
        );
    }

    function updateBorrowersDC(
        IMatchingEngineForAave _mathingEngine,
        address _poolTokenAddress,
        address _user
    ) internal {
        address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.updateBorrowers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }

    function updateSuppliersDC(
        IMatchingEngineForAave _mathingEngine,
        address _poolTokenAddress,
        address _user
    ) internal {
        address(_mathingEngine).functionDelegateCall(
            abi.encodeWithSelector(
                _mathingEngine.updateSuppliers.selector,
                _poolTokenAddress,
                _user
            )
        );
    }
}
