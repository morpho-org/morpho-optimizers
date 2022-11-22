// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./MorphoStorage.sol";

contract ERC1155POC is MorphoStorage {
    error SomethingWentWrong();
    error CannotTransferBorrow();

    enum TokenType {
        SUPPLY_POOL,
        SUPPLY_P2P,
        BORROW_POOL,
        BORROW_P2P
    }

    function balanceOf(address _owner, uint256 _id) external view returns (uint256) {
        (address poolToken, TokenType tokenType) = _getPoolTokenAndSupplyTypeFromId(_id);
        if (tokenType == TokenType.SUPPLY_POOL) {
            return supplyBalanceInOf[poolToken][_owner].onPool;
        } else if (tokenType == TokenType.SUPPLY_P2P) {
            return supplyBalanceInOf[poolToken][_owner].inP2P;
        } else if (tokenType == TokenType.BORROW_POOL) {
            return borrowBalanceInOf[poolToken][_owner].onPool;
        } else {
            return borrowBalanceInOf[poolToken][_owner].inP2P;
        }
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata
    ) external {
        // APPROVAL NOT IMPLEMENTED
        (address poolToken, TokenType tokenType) = _getPoolTokenAndSupplyTypeFromId(_id);
        if (tokenType == TokenType.SUPPLY_POOL) {
            supplyBalanceInOf[poolToken][_from].onPool -= _value;
            supplyBalanceInOf[poolToken][_to].onPool += _value;
        } else if (tokenType == TokenType.SUPPLY_P2P) {
            supplyBalanceInOf[poolToken][_from].inP2P -= _value;
            supplyBalanceInOf[poolToken][_to].inP2P += _value;
        } else revert CannotTransferBorrow();
    }

    function _getPoolTokenAndSupplyTypeFromId(uint256 _id)
        internal
        pure
        returns (address poolToken, TokenType tokenType)
    {
        poolToken = address(uint160(_id));
        uint256 firstTwoBits = _id / (2**254);
        if (firstTwoBits == 0) {
            tokenType = TokenType.SUPPLY_POOL;
        } else if (firstTwoBits == 1) {
            tokenType = TokenType.SUPPLY_P2P;
        } else if (firstTwoBits == 2) {
            tokenType = TokenType.BORROW_POOL;
        } else if (firstTwoBits == 3) {
            tokenType = TokenType.BORROW_P2P;
        } else revert SomethingWentWrong();
    }
}
