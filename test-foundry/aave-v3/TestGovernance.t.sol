// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using WadRayMath for uint256;

    function testShouldDeployContractWithTheRightValues() public {
        assertEq(address(morpho.entryPositionsManager()), address(entryPositionsManager));
        assertEq(address(morpho.exitPositionsManager()), address(exitPositionsManager));
        assertEq(address(morpho.interestRatesManager()), address(interestRatesManager));
        assertEq(address(morpho.addressesProvider()), address(poolAddressesProviderAddress));
        assertEq(
            address(morpho.pool()),
            IPoolAddressesProvider(poolAddressesProviderAddress).getPool()
        );
        assertEq(morpho.maxSortedUsers(), 20);

        (uint256 supply, uint256 borrow, uint256 withdraw, uint256 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, 3e6);
        assertEq(borrow, 3e6);
        assertEq(withdraw, 3e6);
        assertEq(repay, 3e6);
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);

        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        morpho.createMarket(address(supplier1), marketParams);
    }

    function testOnlyOwnerCanCreateMarkets() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);

        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(pools[i], marketParams);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(pools[i], marketParams);
        }

        morpho.createMarket(wEth, marketParams);
    }

    function testShouldCreateMarketWithRightParams() public {
        Types.MarketParameters memory rightParams = Types.MarketParameters(1_000, 3_333);
        Types.MarketParameters memory wrongParams1 = Types.MarketParameters(10_001, 0);
        Types.MarketParameters memory wrongParams2 = Types.MarketParameters(0, 10_001);

        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, wrongParams1);
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, wrongParams2);

        morpho.createMarket(wEth, rightParams);
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(aWeth);
        assertEq(reserveFactor, 1_000);
        assertEq(p2pIndexCursor, 3_333);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(aDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(aDai, 1111);
        }

        morpho.setReserveFactor(aDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        morpho.setReserveFactor(aDai, 1111);
        (uint16 reserveFactor, ) = morpho.marketParameters(aDai);
        assertEq(reserveFactor, 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);
        morpho.createMarket(wEth, marketParams);

        (bool isCreated, , ) = morpho.marketStatus(aAave);

        assertTrue(isCreated);
        assertEq(morpho.p2pSupplyIndex(aAave), WadRayMath.RAY);
        assertEq(morpho.p2pBorrowIndex(aAave), WadRayMath.RAY);
    }

    function testShouldSetMaxGasWithRightValues() public {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: 1,
            borrow: 1,
            withdraw: 1,
            repay: 1
        });

        morpho.setDefaultMaxGasForMatching(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setDefaultMaxGasForMatching(newMaxGas);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setDefaultMaxGasForMatching(newMaxGas);
    }

    function testOnlyOwnerCanSetMaxSortedUsers() public {
        uint256 newMaxSortedUsers = 30;

        morpho.setMaxSortedUsers(newMaxSortedUsers);
        assertEq(morpho.maxSortedUsers(), newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setMaxSortedUsers(newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setMaxSortedUsers(newMaxSortedUsers);
    }

    function testOnlyOwnerShouldFlipMarketStrategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        hevm.prank(address(supplier1));
        morpho.setP2PDisabled(aDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        hevm.prank(address(supplier2));
        morpho.setP2PDisabled(aDai, true);

        morpho.setP2PDisabled(aDai, true);
        assertTrue(morpho.p2pDisabled(aDai));
    }

    function testOnlyOwnerShouldSetEntryManager() public {
        IEntryPositionsManager entryManagerV2 = new EntryPositionsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setEntryPositionsManager(entryManagerV2);

        morpho.setEntryPositionsManager(entryManagerV2);
        assertEq(address(morpho.entryPositionsManager()), address(entryManagerV2));
    }

    // TODO: add rewards
    // function testOnlyOwnerShouldSetRewardsManager() public {
    //     IRewardsManager rewardsManagerV2 = new RewardsManagerOnMainnetAndAvalanche(
    //         pool,
    //         IMorpho(address(morpho))
    //     );

    //     hevm.prank(address(0));
    //     hevm.expectRevert("Ownable: caller is not the owner");
    //     morpho.setRewardsManager(rewardsManagerV2);

    //     morpho.setRewardsManager(rewardsManagerV2);
    //     assertEq(address(morpho.rewardsManager()), address(rewardsManagerV2));
    // }

    function testOnlyOwnerShouldSetInterestRatesManager() public {
        IInterestRatesManager interestRatesV2 = new InterestRatesManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setInterestRatesManager(interestRatesV2);

        morpho.setInterestRatesManager(interestRatesV2);
        assertEq(address(morpho.interestRatesManager()), address(interestRatesV2));
    }

    function testOnlyOwnerShouldSetIncentivesVault() public {
        IIncentivesVault incentivesVaultV2 = new IncentivesVault(
            IMorpho(address(morpho)),
            morphoToken,
            address(2),
            dumbOracle
        );

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIncentivesVault(incentivesVaultV2);

        morpho.setIncentivesVault(incentivesVaultV2);
        assertEq(address(morpho.incentivesVault()), address(incentivesVaultV2));
    }

    function testOnlyOwnerShouldSetTreasuryVault() public {
        address treasuryVaultV2 = address(2);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setTreasuryVault(treasuryVaultV2);

        morpho.setTreasuryVault(treasuryVaultV2);
        assertEq(address(morpho.treasuryVault()), treasuryVaultV2);
    }

    function testOnlyOwnerCanSetPauseStatusForAllMarkets() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setPauseStatusForAllMarkets(true);

        morpho.setPauseStatusForAllMarkets(true);
    }

    function testOnlyOwnerCanSetClaimRewardsStatus() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setClaimRewardsPauseStatus(true);

        morpho.setClaimRewardsPauseStatus(true);
        assertTrue(morpho.isClaimRewardsPaused());
    }
}
