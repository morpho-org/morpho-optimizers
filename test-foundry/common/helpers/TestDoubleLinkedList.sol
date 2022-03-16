// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@contracts/common/libraries/DoubleLinkedList.sol";

contract TestDoubleLinkedList {
    using DoubleLinkedList for DoubleLinkedList.List;

    DoubleLinkedList.List private list;

    function getValueOf(address _id) external view returns (uint256) {
        return list.getValueOf(_id);
    }

    function getHead() external view returns (address) {
        return list.getHead();
    }

    function getTail() external view returns (address) {
        return list.getTail();
    }

    function getNext(address _id) external view returns (address) {
        return list.getNext(_id);
    }

    function getPrev(address _id) external view returns (address) {
        return list.getPrev(_id);
    }

    function remove(address _id) external returns (bool) {
        return list.remove(_id);
    }

    function insertSorted(
        address _id,
        uint256 _value,
        uint256 _maxIterations
    ) external {
        list.insertSorted(_id, _value, _maxIterations);
    }
}
