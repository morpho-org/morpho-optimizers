// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/ILogic.sol";

library LogicDCs {
    /// @notice Delegate calls the supply function of the logic contract.
    /// @param _logic The logic contract.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supplyDC(
        ILogic _logic,
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal {
        (bool success, bytes memory data) = address(_logic).delegatecall(
            abi.encodeWithSelector(
                _logic.supply.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );
        _verifyCallResult(success, data, "Address: low-level delegate call failed");
    }

    /// @notice Delegate calls the borrow function of the logic contract.
    /// @param _logic The logic contract.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrowDC(
        ILogic _logic,
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal {
        (bool success, bytes memory data) = address(_logic).delegatecall(
            abi.encodeWithSelector(
                _logic.borrow.selector,
                _poolTokenAddress,
                _amount,
                _maxGasToConsume
            )
        );
        _verifyCallResult(success, data, "Address: low-level delegate call failed");
    }

    /// @notice Delegate calls the withdraw function of the logic contract.
    /// @param _logic The logic contract.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function withdrawDC(
        ILogic _logic,
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasToConsume
    ) internal {
        (bool success, bytes memory data) = address(_logic).delegatecall(
            abi.encodeWithSelector(
                _logic.withdraw.selector,
                _poolTokenAddress,
                _amount,
                _supplier,
                _receiver,
                _maxGasToConsume
            )
        );
        _verifyCallResult(success, data, "Address: low-level delegate call failed");
    }

    /// @notice Delegate calls the repay function of the logic contract.
    /// @param _logic The logic contract.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function repayDC(
        ILogic _logic,
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal {
        (bool success, bytes memory data) = address(_logic).delegatecall(
            abi.encodeWithSelector(
                _logic.repay.selector,
                _poolTokenAddress,
                _user,
                _amount,
                _maxGasToConsume
            )
        );
        _verifyCallResult(success, data, "Address: low-level delegate call failed");
    }

    /// @notice Delegate calls the liquidate function of the logic contract.
    /// @param _logic The logic contract.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidateDC(
        ILogic _logic,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) internal returns (uint256) {
        (bool success, bytes memory data) = address(_logic).delegatecall(
            abi.encodeWithSelector(
                _logic.liquidate.selector,
                _poolTokenBorrowedAddress,
                _poolTokenCollateralAddress,
                _borrower,
                _amount
            )
        );
        _verifyCallResult(success, data, "Address: low-level delegate call failed");

        return abi.decode(data, (uint256));
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure {
        if (!success) {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else revert(errorMessage);
        }
    }
}
