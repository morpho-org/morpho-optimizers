// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

/// @title Delegate Call Library.
/// @dev Library to perform delegate calls inspired by the OZ Address library: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol.
library DelegateCall {
    /// ERRORS ///

    /// @notice Thrown when a low delegate call has failed without error message.
    error LowLevelDelegateCallFailed();

    /// INTERNAL ///

    /// @dev Performs a low-level delegate call to the `_target` contract.
    /// @dev Note: Unlike the OZ's library this function does not check if the `_target` is a contract. It is the responsibility of the caller to ensure that the `_target` is a contract.
    /// @param _target The address of the target contract.
    /// @param _data The date to pass to the function called on the target contract.
    /// @return The return data from the function called on the target contract.
    function functionDelegateCall(address _target, bytes memory _data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = _target.delegatecall(_data);
        return verifyCallResult(success, returndata);
    }

    /// @dev Verifies the success of the call or returns an error.
    /// @param _success Whether the call is succesful or not.
    /// @param _returndata The return data from the call.
    function verifyCallResult(bool _success, bytes memory _returndata)
        internal
        pure
        returns (bytes memory)
    {
        if (_success) return _returndata;
        else {
            // Look for revert reason and bubble it up if present.
            if (_returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly.

                assembly {
                    let returndata_size := mload(_returndata)
                    revert(add(32, _returndata), returndata_size)
                }
            } else revert LowLevelDelegateCallFailed();
        }
    }
}
