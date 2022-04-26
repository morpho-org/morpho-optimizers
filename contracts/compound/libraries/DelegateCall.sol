// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library DelegateCall {
    error LowLevelDelegateCallFailed();

    function functionDelegateCall(address _target, bytes memory _data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) = _target.delegatecall(_data);
        return verifyCallResult(success, returndata);
    }

    function verifyCallResult(bool success, bytes memory returndata)
        internal
        pure
        returns (bytes memory)
    {
        if (success) return returndata;
        else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else revert LowLevelDelegateCallFailed();
        }
    }
}
