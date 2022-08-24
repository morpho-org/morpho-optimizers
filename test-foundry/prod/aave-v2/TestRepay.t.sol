// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    struct RepayTest {
        ERC20 collateral;
        IAToken collateralPoolToken;
        uint256 collateralDecimals;
        ERC20 borrowed;
        IAToken borrowedPoolToken;
        IVariableDebtToken borrowedVariablePoolToken;
        uint256 borrowedDecimals;
        uint256 collateralLtv;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 borrowedAmount;
        uint256 collateralAmount;
        uint256 borrowedBalanceBefore;
        uint256 borrowedBalanceAfter;
        uint256 morphoBalanceOnPoolBefore;
        uint256 p2pBorrowIndex;
        uint256 poolBorrowIndex;
        uint256 borrowRatePerYear;
        uint256 p2pBorrowRatePerYear;
        uint256 poolBorrowRatePerYear;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 borrowedOnPoolBefore;
        uint256 borrowedInP2PBefore;
        uint256 totalBorrowedBefore;
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalBorrowedAfter;
    }

    function _setUpRepayTest(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal returns (RepayTest memory test) {
        test.borrowedPoolToken = IAToken(_borrowedPoolToken);
        test.collateralPoolToken = IAToken(_collateralPoolToken);

        // test.borrowCap = morpho.comptroller().borrowCaps(address(test.borrowedPoolToken));

        test.collateral = ERC20(test.collateralPoolToken.UNDERLYING_ASSET_ADDRESS());
        test.borrowed = ERC20(test.borrowedPoolToken.UNDERLYING_ASSET_ADDRESS());
        test.borrowedVariablePoolToken = IVariableDebtToken(
            pool.getReserveData(address(test.borrowed)).variableDebtTokenAddress
        );
        test.borrowedDecimals = test.borrowed.decimals();

        test.collateralPrice = oracle.getAssetPrice(address(test.collateral));
        test.borrowedPrice = oracle.getAssetPrice(address(test.borrowed));

        (test.collateralLtv, , , test.collateralDecimals, ) = morpho
        .pool()
        .getConfiguration(address(test.collateral))
        .getParamsMemory();

        test.borrowedBalanceBefore = test.borrowed.balanceOf(address(borrower1));
        test.morphoBalanceOnPoolBefore = test.borrowedPoolToken.balanceOf(address(morpho));

        test.borrowedAmount = _boundBorrowedAmount(
            _amount,
            _borrowedPoolToken,
            address(test.borrowed),
            test.borrowedDecimals
        );
    }

    function _testShouldRepayMarketP2PAndFromPool(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal {
        RepayTest memory test = _setUpRepayTest(_borrowedPoolToken, _collateralPoolToken, _amount);

        test.collateralAmount =
            _getMinimumCollateralAmount(
                test.borrowedAmount,
                test.borrowedPrice,
                test.borrowedDecimals,
                test.collateralPrice,
                test.collateralDecimals,
                test.collateralLtv
            ) +
            10**(test.collateralDecimals - 4);
        _tip(address(test.collateral), address(borrower1), test.collateralAmount);

        borrower1.approve(address(test.collateral), test.collateralAmount);
        borrower1.supply(address(test.collateralPoolToken), test.collateralAmount);
        borrower1.borrow(address(test.borrowedPoolToken), test.borrowedAmount);

        test.borrowedBalanceAfter = test.borrowed.balanceOf(address(borrower1));
        test.p2pBorrowIndex = morpho.p2pBorrowIndex(address(test.borrowedPoolToken));
        (, , test.poolBorrowIndex) = morpho.poolIndexes(address(test.borrowedPoolToken));
        test.borrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(
            address(test.borrowedPoolToken),
            address(borrower1)
        );
        (, test.p2pBorrowRatePerYear, , test.poolBorrowRatePerYear) = lens.getRatesPerYear(
            address(test.borrowedPoolToken)
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.borrowBalanceInOf(
            address(test.borrowedPoolToken),
            address(borrower1)
        );

        test.borrowedInP2PBefore = test.balanceInP2P.rayMul(test.p2pBorrowIndex);
        test.borrowedOnPoolBefore = test.balanceOnPool.rayMul(test.poolBorrowIndex);
        test.totalBorrowedBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        vm.roll(block.number + 5_000);
        vm.warp(block.timestamp + 60 * 60 * 24);

        morpho.updateIndexes(address(test.borrowedPoolToken));

        vm.roll(block.number + 5_000);
        vm.warp(block.timestamp + 60 * 60 * 24);

        assertEq(
            test.borrowed.balanceOf(address(borrower1)),
            test.borrowedAmount,
            "unexpected borrowed balance before repay"
        );

        (test.borrowedInP2PAfter, test.borrowedOnPoolAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        assertGe(
            test.totalBorrowedAfter,
            test.totalBorrowedBefore,
            "unexpected borrowed amount before repay"
        );

        _tip(
            address(test.borrowed),
            address(borrower1),
            test.totalBorrowedAfter - test.borrowed.balanceOf(address(borrower1))
        );
        borrower1.approve(address(test.borrowed), type(uint256).max);
        borrower1.repay(address(test.borrowedPoolToken), type(uint256).max);

        assertApproxEqAbs(
            test.borrowed.balanceOf(address(borrower1)),
            0,
            10**(test.borrowedDecimals / 2),
            "unexpected borrowed balance after repay"
        );

        (test.borrowedInP2PAfter, test.borrowedOnPoolAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        assertEq(test.borrowedOnPoolAfter, 0, "unexpected pool borrowed amount after repay");
        assertEq(test.borrowedInP2PAfter, 0, "unexpected p2p borrowed amount after repay");
        assertEq(test.totalBorrowedAfter, 0, "unexpected total borrowed after repay");
    }

    function testShouldRepayAmountP2PAndFromPool(
        uint8 _borrowMarketIndex,
        uint8 _collateralMarketIndex,
        uint96 _amount
    ) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        address[] memory activeCollateralMarkets = getAllFullyActiveCollateralMarkets();

        _borrowMarketIndex = uint8(_borrowMarketIndex % activeMarkets.length);
        _collateralMarketIndex = uint8(_collateralMarketIndex % activeCollateralMarkets.length);

        _testShouldRepayMarketP2PAndFromPool(
            activeMarkets[_borrowMarketIndex],
            activeCollateralMarkets[_collateralMarketIndex],
            _amount
        );
    }

    function testShouldNotRepayZeroAmount() public {
        address[] memory markets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            RepayTest memory test;
            test.borrowedPoolToken = IAToken(markets[marketIndex]);

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            borrower1.repay(address(test.borrowedPoolToken), 0);
        }
    }
}
