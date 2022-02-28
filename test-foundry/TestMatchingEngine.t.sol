// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

// import "@config/Config.sol";
import "lib/ds-test/src/test.sol";
import "@contracts/aave/MatchingEngineForAave.sol";
import "@contracts/common/libraries/DoubleLinkedList.sol";

import "hardhat/console.sol";

contract MockScaledBalanceToken {
    function scaledTotalSupply() external pure returns (uint256) {
        return 1;
    }
}

contract MockRewardsManager {
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) external {}
}

contract TestMatchingEngine is DSTest, MatchingEngineForAave {
    using DoubleLinkedList for DoubleLinkedList.List;
    address private token;

    constructor() {
        rewardsManager = IRewardsManager(address(new MockRewardsManager()));
    }

    function setUp() public {
        token = address(new MockScaledBalanceToken()); // effectively reinitializes the state
    }

    // overrides to isolate tested funcs

    // when modifing onPool and inP2P values, both should be removed then insert sorted
    function test_updateSuppliers() public {
        address user = address(123456789);
        uint256 value = 1000;
        uint256 otherValue = 2000;
        uint256 newValue = 3000;
        uint256 newOtherValue = 4000;

        supplyBalanceInOf[token][user].onPool = value;
        supplyBalanceInOf[token][user].inP2P = otherValue;
        updateSuppliers(token, user);

        assertEq(suppliersOnPool[token].getValueOf(user), value, "pool not updated");
        assertEq(suppliersInP2P[token].getValueOf(user), otherValue, "p2p not updated");

        supplyBalanceInOf[token][user].onPool = newValue;
        supplyBalanceInOf[token][user].inP2P = newOtherValue;

        updateSuppliers(token, user);

        assertEq(suppliersOnPool[token].getValueOf(user), newValue, "pool not updated");
        assertEq(suppliersInP2P[token].getValueOf(user), newOtherValue, "p2p not updated");

        // check that user value has been updated by checking there is only one user in the list
        require(
            suppliersOnPool[token].getHead() == suppliersOnPool[token].getTail(),
            "not removed prev value"
        );
        require(suppliersOnPool[token].getNext(user) == suppliersOnPool[token].getPrev(user));
        require(suppliersOnPool[token].getNext(user) == address(0));
    }
}
