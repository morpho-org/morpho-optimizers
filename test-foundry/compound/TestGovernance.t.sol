// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using CompoundMath for uint256;

    function testShoudDeployContractWithTheRightValues() public {
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
        hevm.expectRevert(abi.encodeWithSignature("MarketCreationFailedOnCompound()"));
        morpho.createMarket(address(supplier1));
    }

    function testOnlyOwnerCanCreateMarkets() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(pools[i]);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(pools[i]);
        }

        morpho.createMarket(cAave);
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
        morpho.createMarket(cAave);

        (bool isCreated, , ) = morpho.marketStatuses(cAave);

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
        MorphoStorage.MaxGasForMatching memory newMaxGas = MorphoStorage.MaxGasForMatching({
            supply: 1,
            borrow: 1,
            withdraw: 1,
            repay: 1
        });

        morpho.setMaxGasForMatching(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho.maxGasForMatching();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setMaxGasForMatching(newMaxGas);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setMaxGasForMatching(newMaxGas);
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
        supplier1.setNoP2P(cDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setNoP2P(cDai, true);

        morpho.setNoP2P(cDai, true);
        assertTrue(morpho.noP2P(cDai));
    }
}
