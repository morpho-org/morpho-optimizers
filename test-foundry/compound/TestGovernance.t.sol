// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using CompoundMath for uint256;

    function testShouldDeployContractWithTheRightValues() public {
        assertEq(
            morpho.p2pSupplyIndex(cDai),
            2 * 10**(16 + ERC20(ICToken(cDai).underlying()).decimals() - 8)
        );
        assertEq(
            morpho.p2pBorrowIndex(cDai),
            2 * 10**(16 + ERC20(ICToken(cDai).underlying()).decimals() - 8)
        );
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);

        hevm.expectRevert(abi.encodeWithSignature("MarketCreationFailedOnCompound()"));
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

        morpho.createMarket(cAave, marketParams);
    }

    function testShouldCreateMarketWithRightParams() public {
        Types.MarketParameters memory rightParams = Types.MarketParameters(1_000, 3_333);
        Types.MarketParameters memory wrongParams1 = Types.MarketParameters(10_001, 0);
        Types.MarketParameters memory wrongParams2 = Types.MarketParameters(0, 10_001);

        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(cAave, wrongParams1);
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(cAave, wrongParams2);

        morpho.createMarket(cAave, rightParams);
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(cAave);
        assertEq(reserveFactor, 1_000);
        assertEq(p2pIndexCursor, 3_333);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(cDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(cDai, 1111);
        }

        morpho.setReserveFactor(cDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        morpho.setReserveFactor(cDai, 1111);
        (uint16 reserveFactor, ) = morpho.marketParameters(cDai);
        assertEq(reserveFactor, 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        ICToken cToken = ICToken(cAave);
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);
        morpho.createMarket(cAave, marketParams);

        (bool isCreated, , , , , , , ) = morpho.marketStatus(cAave);

        assertTrue(isCreated);
        assertEq(
            morpho.p2pSupplyIndex(cAave),
            2 * 10**(16 + ERC20(cToken.underlying()).decimals() - 8)
        );
        assertEq(
            morpho.p2pBorrowIndex(cAave),
            2 * 10**(16 + ERC20(cToken.underlying()).decimals() - 8)
        );
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
        supplier1.setP2PDisabled(cDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setP2PDisabled(cDai, true);

        morpho.setP2PDisabled(cDai, true);
        assertTrue(morpho.p2pDisabled(cDai));
    }

    function testOnlyOwnerShouldSetPositionsManager() public {
        IPositionsManager positionsManagerV2 = new PositionsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setPositionsManager(positionsManagerV2);

        morpho.setPositionsManager(positionsManagerV2);
        assertEq(address(morpho.positionsManager()), address(positionsManagerV2));
    }

    function testOnlyOwnerShouldSetRewardsManager() public {
        IRewardsManager rewardsManagerV2 = new RewardsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setRewardsManager(rewardsManagerV2);

        morpho.setRewardsManager(rewardsManagerV2);
        assertEq(address(morpho.rewardsManager()), address(rewardsManagerV2));
    }

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
            comptroller,
            IMorpho(address(morpho)),
            morphoToken,
            address(1),
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

    function testOnlyOwnerCanSetClaimRewardsStatus() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setClaimRewardsPauseStatus(true);

        morpho.setClaimRewardsPauseStatus(true);
        assertTrue(morpho.isClaimRewardsPaused());
    }
}
