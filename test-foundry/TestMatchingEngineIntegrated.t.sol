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

// external contracts are called from forked chain (semi-isolated approach)
contract TestMatchingEngineIntegrated is DSTest, MatchingEngineForAave, Config {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    address private eoa1;
    address private eoa2;
    User private user;
    uint256 private normalizer;
    uint256 private p2pRate;

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
        marketsManager.createMarket(dai, 1000);
    }

    function setUp() public {
        normalizer = lendingPool.getReserveNormalizedIncome(dai);
        p2pRate = marketsManager.supplyP2PExchangeRate(aDai);
        supplyBalanceInOf[aDai][address(1)].onPool = 0;
        supplyBalanceInOf[aDai][address(2)].onPool = 0;
        supplyBalanceInOf[aDai][address(1)].inP2P = 0;
        supplyBalanceInOf[aDai][address(2)].inP2P = 0;
        emptyList(suppliersOnPool[aDai]);
        emptyList(suppliersInP2P[aDai]);
    }

    // multiple suppliers should be moved to p2p
    function test_match_suppliers() public {
        uint256 expectedInUnderlying = uint256(1 ether).mulWadByRay(normalizer);
        uint256 expectedInP2P = expectedInUnderlying.divWadByRay(p2pRate);

        suppliersOnPool[aDai].insertSorted(address(1), 1 ether, 20);
        suppliersOnPool[aDai].insertSorted(address(2), 1 ether, 20);
        supplyBalanceInOf[aDai][address(1)].onPool = 1 ether;
        supplyBalanceInOf[aDai][address(2)].onPool = 1 ether;

        this.matchSuppliers(
            IAToken(aDai),
            IERC20(dai),
            2 * expectedInUnderlying,
            type(uint256).max
        );

        assertEq(supplyBalanceInOf[aDai][address(1)].onPool, 0, "supplyBalanceInOf 1");
        assertEq(supplyBalanceInOf[aDai][address(2)].onPool, 0, "supplyBalanceInOf 2");
        assertEq(suppliersInP2P[aDai].getValueOf(address(1)), expectedInP2P, "array value 1");
        assertEq(suppliersInP2P[aDai].getValueOf(address(2)), expectedInP2P, "array value 2");
    }

    // should match delta first
    function test_match_suppliers_delta() public {
        uint256 expectedInUnderlying = uint256(1 ether).mulWadByRay(normalizer);
        uint256 expectedInP2P = expectedInUnderlying.divWadByRay(p2pRate);
        p2ps[aDai].supplyDelta = 2 * expectedInP2P;

        this.matchSuppliers(IAToken(aDai), IERC20(dai), expectedInUnderlying, type(uint256).max);

        assertEq(p2ps[aDai].supplyDelta, expectedInP2P, "supplyDelta not matched as expected");
        assertEq(p2ps[aDai].supplyAmount, expectedInP2P);
        require(suppliersInP2P[aDai].getHead() == address(0));
    }

    /// Internal ///

    function writeBalanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }

    function emptyList(DoubleLinkedList.List storage list) private {
        address head = list.getHead();
        while (head != address(0)) {
            list.remove(head);
            head = list.getHead();
        }
    }
}
