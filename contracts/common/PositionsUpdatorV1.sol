// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./libraries/DoubleLinkedList.sol";

import "./interfaces/IPositionsUpdator.sol";

import "./PositionsUpdatorStorageV1.sol";

contract PositionsUpdatorV1 is IPositionsUpdator, PositionsUpdatorStorageV1 {
    using DoubleLinkedList for DoubleLinkedList.List;

    /* Modifiers */

    /** @dev Prevents a user to call function allowed for the markets manager.
     */
    modifier onlyPositionsManager() {
        require(msg.sender == address(positionsManager), "only-positions-manager");
        _;
    }

    /* Initializer */

    /** @dev Initializes the proxy contract.
     *  @param _positionsManager The new address of the `positionsManager`.
     */
    function initialize(address _positionsManager) public initializer {
        __Ownable_init();
        positionsManager = IPositionsManager(_positionsManager);
    }

    /* External */

    /** @dev Updates the `maxIterations` number.
     *  @param _maxIterations The new `maxIterations`.
     */
    function updateMaxIterations(uint16 _maxIterations) external override onlyPositionsManager {
        maxIterations = _maxIterations;
    }

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function updateBorrowerPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyPositionsManager
    {
        uint256 onPool = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = data[uint8(UserType.BORROWERS_ON_POOL)][_poolTokenAddress]
            .getValueOf(_account);
        uint256 formerValueInP2P = data[uint8(UserType.BORROWERS_IN_P2P)][_poolTokenAddress]
            .getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged)
            data[uint8(UserType.BORROWERS_ON_POOL)][_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            data[uint8(UserType.BORROWERS_ON_POOL)][_poolTokenAddress].insertSorted(
                _account,
                onPool,
                maxIterations
            );

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged)
            data[uint8(UserType.BORROWERS_IN_P2P)][_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            data[uint8(UserType.BORROWERS_IN_P2P)][_poolTokenAddress].insertSorted(
                _account,
                inP2P,
                maxIterations
            );
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function updateSupplierPositions(address _poolTokenAddress, address _account)
        external
        override
        onlyPositionsManager
    {
        uint256 onPool = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = data[uint8(UserType.SUPPLIERS_ON_POOL)][_poolTokenAddress]
            .getValueOf(_account);
        uint256 formerValueInP2P = data[uint8(UserType.SUPPLIERS_IN_P2P)][_poolTokenAddress]
            .getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged)
            data[uint8(UserType.SUPPLIERS_ON_POOL)][_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            data[uint8(UserType.SUPPLIERS_ON_POOL)][_poolTokenAddress].insertSorted(
                _account,
                onPool,
                maxIterations
            );

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged)
            data[uint8(UserType.SUPPLIERS_IN_P2P)][_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            data[uint8(UserType.SUPPLIERS_IN_P2P)][_poolTokenAddress].insertSorted(
                _account,
                inP2P,
                maxIterations
            );
    }

    function getValueOf(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external view override returns (uint256) {
        return data[_positionType][_poolTokenAddress].getValueOf(_account);
    }

    function getFirst(uint8 _positionType, address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return data[_positionType][_poolTokenAddress].getHead();
    }

    function getLast(uint8 _positionType, address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return data[_positionType][_poolTokenAddress].getTail();
    }

    function getNext(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external view override returns (address) {
        return data[_positionType][_poolTokenAddress].getNext(_account);
    }

    function getPrev(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external view override returns (address) {
        return data[_positionType][_poolTokenAddress].getPrev(_account);
    }

    /* Internal */

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
