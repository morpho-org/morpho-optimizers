// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

// import "@config/Config.sol";
import "lib/ds-test/src/test.sol";
import "@contracts/aave/MatchingEngineForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/common/libraries/DoubleLinkedList.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "@config/Config.sol";
import "@contracts/common/SwapManager.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "./utils/MorphoToken.sol";
import "./utils/User.sol";
import "./utils/UniswapPoolCreator.sol";
import {MockRewardsManager} from "./TestMatchingEngineIsolated.t.sol";
import "./utils/HEVM.sol";

import "hardhat/console.sol";

// contract MockPositionsManager is PositionsManagerForAave {
//     constructor(
//         address _marketsManager,
//         address _lendingPoolAddressesProvider,
//         ISwapManager _swapManager,
//         MaxGas memory _maxGas
//     )
//         PositionsManagerForAave(
//             _marketsManager,
//             _lendingPoolAddressesProvider,
//             _swapManager,
//             _maxGas
//         )
//     {}

//     function changeMarketManager(address newMm) external {}

//     // function setThreshold(address _poolTokenAddress, uint256 _newThreshold) external override {}
// }

// external contracts are called from forked chain (semi-isolated approach)
contract TestMatchingEngineIntegrated is DSTest, MatchingEngineForAave, Config {
    using DoubleLinkedList for DoubleLinkedList.List;
    address private token;
    User user;

    HEVM public hevm = HEVM(HEVM_ADDRESS);

    // setting up with addresses of forked chain
    constructor() {
        maxGas = PositionsManagerForAaveStorage.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 1.5e6,
            repay: 1.5e6
        });
        marketsManager = IMarketsManagerForAave(
            address(new MarketsManagerForAave(lendingPoolAddressesProviderAddress))
        );
        addressesProvider = ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        rewardsManager = IRewardsManager(address(new MockRewardsManager()));

        address pos = address(
            new PositionsManagerForAave(
                address(marketsManager),
                lendingPoolAddressesProviderAddress,
                ISwapManager(address(1)),
                maxGas
            )
        );
        marketsManager.setPositionsManager(address(this));
        user = new User(
            PositionsManagerForAave(pos),
            MarketsManagerForAave(address(marketsManager)),
            RewardsManager(address(rewardsManager))
        );
        writeBalanceOf(address(user), dai, 100_000_000 ether);
        user.aaveSupply(dai, 1000 ether);
        user.sendTokens(aDai, address(this), 1000 ether);
    }

    function test_match_suppliers() public {
        marketsManager.createMarket(dai, 1000);

        suppliersOnPool[aDai].insertSorted(address(1), 1 ether, 20);
        suppliersOnPool[aDai].insertSorted(address(2), 1 ether, 20);
        supplyBalanceInOf[aDai][address(1)].onPool = 1 ether;
        supplyBalanceInOf[aDai][address(2)].onPool = 1 ether;

        // marketsManager.setPositionsManager(address(this));
        this.matchSuppliers(IAToken(aDai), IERC20(dai), 2 ether, type(uint256).max);

        assertEq(supplyBalanceInOf[aDai][address(1)].onPool, 0, "supplyBalanceInOf 1");
        assertEq(supplyBalanceInOf[aDai][address(2)].onPool, 0, "supplyBalanceInOf 2");
        assertEq(suppliersInP2P[aDai].getValueOf(address(1)), 1 ether, "array value 1");
        assertEq(suppliersInP2P[aDai].getValueOf(address(2)), 1 ether, "array value 2");
    }

    /// Internal ///

    function writeBalanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }
}
