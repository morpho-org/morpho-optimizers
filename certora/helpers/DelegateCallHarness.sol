// This is a version of delegateCall with the functionality removed to avoid analysis issues within the tool

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

library DelegateCall {
    /// ERRORS ///

    /// @notice Thrown when a low delegate call has failed without error message.
    error LowLevelDelegateCallFailed();
    bytes4 constant LowLevelDelegateCallFailedError = 0x06f7035e; // bytes4(keccak256("LowLevelDelegateCallFailed()"))

    /// INTERNAL ///

    // this function will just return the _data given to it. We can potentially use summaries or other solidity operations to tweek this data
    function functionDelegateCall(address _target, bytes memory _data)
        internal
        returns (bytes memory returnData)
    {
        returnData = _data;
    }
}
