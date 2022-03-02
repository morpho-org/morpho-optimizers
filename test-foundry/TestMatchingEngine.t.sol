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

    address public constant UNDERLYING_ASSET_ADDRESS = address(42);
}

contract MockRewardsManager {
    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) external {}
}

contract MockProtocolDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        )
    {
        aTokenAddress = address(1);
        stableDebtTokenAddress = address(2);
        variableDebtTokenAddress = address(3);
    }
}

contract TestMatchingEngine is DSTest, MatchingEngineForAave {
    using DoubleLinkedList for DoubleLinkedList.List;
    address private token;

    constructor() {
        rewardsManager = IRewardsManager(address(new MockRewardsManager()));
        dataProvider = IProtocolDataProvider(address(new MockProtocolDataProvider()));
    }

    function setUp() public {
        token = address(new MockScaledBalanceToken()); // effectively reinitializes the state
    }

    // overrides to isolate tested funcs

    // when modifing onPool and inP2P values, both should be removed then insert sorted
    function test_update_suppliers() public {
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

    // when modifing onPool and inP2P values, both should be removed then insert sorted
    function test_update_borrowers() public {
        address user = address(123456789);
        uint256 value = 1000;
        uint256 otherValue = 2000;
        uint256 newValue = 3000;
        uint256 newOtherValue = 4000;

        borrowBalanceInOf[token][user].onPool = value;
        borrowBalanceInOf[token][user].inP2P = otherValue;
        updateBorrowers(token, user);

        assertEq(borrowersOnPool[token].getValueOf(user), value, "pool not updated");
        assertEq(borrowersInP2P[token].getValueOf(user), otherValue, "p2p not updated");

        borrowBalanceInOf[token][user].onPool = newValue;
        borrowBalanceInOf[token][user].inP2P = newOtherValue;

        updateBorrowers(token, user);

        assertEq(borrowersOnPool[token].getValueOf(user), newValue, "pool not updated");
        assertEq(borrowersInP2P[token].getValueOf(user), newOtherValue, "p2p not updated");

        // check that user value has been updated by checking there is only one user in the list
        require(
            borrowersOnPool[token].getHead() == borrowersOnPool[token].getTail(),
            "not removed prev value"
        );
        require(borrowersOnPool[token].getNext(user) == borrowersOnPool[token].getPrev(user));
        require(borrowersOnPool[token].getNext(user) == address(0));
    }

    // should match p2p delta only when delta > amount
    // function test_match_suppliers() public {
    //     this.matchSuppliers(IAToken(token), IERC20(address(new MockScaledBalanceToken())), 1000, 0);
    //     deltas[token] = Delta({
    //         supplyDelta : 2000
    //     });
    // }
}
