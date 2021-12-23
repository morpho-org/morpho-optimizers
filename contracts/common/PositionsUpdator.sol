// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IPositionsUpdator.sol";
import "./interfaces/IPositionsUpdatorLogic.sol";
import "./libraries/ErrorsForPositionsUpdator.sol";
import "./PositionsUpdatorStorage.sol";

contract PositionsUpdator is IPositionsUpdator, PositionsUpdatorStorage {
    using Address for address;

    /* Constructor */

    constructor(
        address _positionsManager,
        address _positionsUpdatorLogic,
        uint256 _maxIterations
    ) {
        positionsManager = IPositionsManager(_positionsManager);
        positionsUpdatorLogic = IPositionsUpdatorLogic(_positionsUpdatorLogic);
        maxIterations = _maxIterations;
    }

    /** @dev Updates the `positionsUpdatorLogic` address.
     *  @param _positionsUpdatorLogic The new address of the `positionsUpdatorLogic`.
     */
    function updatePositionsUpdatorLogic(address _positionsUpdatorLogic) external onlyOwner {
        positionsUpdatorLogic = IPositionsUpdatorLogic(_positionsUpdatorLogic);
    }

    /** @dev Updates the `maxIterations` number.
     *  @param _maxIterations The new `maxIterations`.
     */
    function updateMaxIterations(uint256 _maxIterations) external onlyOwner {
        maxIterations = _maxIterations;
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function updateBorrowerPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyOwner
    {
        address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.updateBorrowerPositions.selector,
                _poolTokenAddress,
                _account,
                maxIterations
            ),
            ErrorsPU.PU_UPDATE_BORROWER_POSITIONS_FAIL
        );
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function updateSupplierPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyOwner
    {
        address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.updateSupplierPositions.selector,
                _poolTokenAddress,
                _account,
                maxIterations
            ),
            ErrorsPU.PU_UPDATE_SUPPLIER_POSITIONS_FAIL
        );
    }

    function getBorrowerAccountOnPool(address _poolTokenAddress)
        external
        override
        onlyOwner
        returns (address)
    {
        bytes memory result = address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.getBorrowerAccountOnPool.selector,
                _poolTokenAddress
            ),
            ErrorsPU.PU_GET_BORROWER_ACCOUNT_ON_POOL
        );
        return abi.decode(result, (address));
    }

    function getBorrowerAccountInP2P(address _poolTokenAddress)
        external
        override
        onlyOwner
        returns (address)
    {
        bytes memory result = address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.getBorrowerAccountInP2P.selector,
                _poolTokenAddress
            ),
            ErrorsPU.PU_GET_BORROWER_ACCOUNT_IN_P2P
        );
        return abi.decode(result, (address));
    }

    function getSupplierAccountOnPool(address _poolTokenAddress)
        external
        override
        onlyOwner
        returns (address)
    {
        bytes memory result = address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.getSupplierAccountOnPool.selector,
                _poolTokenAddress
            ),
            ErrorsPU.PU_GET_SUPPLIER_ACCOUNT_ON_POOL
        );
        return abi.decode(result, (address));
    }

    function getSupplierAccountInP2P(address _poolTokenAddress)
        external
        override
        onlyOwner
        returns (address)
    {
        bytes memory result = address(positionsUpdatorLogic).functionDelegateCall(
            abi.encodeWithSelector(
                positionsUpdatorLogic.getSupplierAccountInP2P.selector,
                _poolTokenAddress
            ),
            ErrorsPU.PU_GET_SUPPLIER_ACCOUNT_IN_P2P
        );
        return abi.decode(result, (address));
    }
}
