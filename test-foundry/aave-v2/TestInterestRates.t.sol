// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v2/InterestRatesManager.sol";
import "forge-std/Test.sol";

contract TestInterestRates is InterestRatesManager, Test {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant RAY = 1e27;

    uint256 public p2pSupplyIndexTest = 1 * RAY;
    uint256 public p2pBorrowIndexTest = 1 * RAY;
    uint256 public poolSupplyIndexTest = 2 * RAY;
    uint256 public poolBorrowIndexTest = 3 * RAY;
    uint256 public lastPoolSupplyIndexTest = 1 * RAY;
    uint256 public lastPoolBorrowIndexTest = 1 * RAY;
    uint256 public reserveFactor0PerCentTest = 0;
    uint256 public reserveFactor50PerCentTest = 5_000;
    uint256 public p2pIndexCursorTest = 3_333;

    // prettier-ignore
    function computeP2PIndexes(InterestRatesManager.Params memory _params)
        public
        pure
        returns (uint256 p2pSupplyIndex_, uint256 p2pBorrowIndex_)
    {
        uint256 poolSupplyGrowthFactor = ((_params.poolSupplyIndex * RAY) / _params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = ((_params.poolBorrowIndex * RAY) / _params.lastPoolBorrowIndex);
        uint256 p2pIncrease = ((MAX_BASIS_POINTS - _params.p2pIndexCursor) * poolSupplyGrowthFactor + _params.p2pIndexCursor * poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
        uint256 shareOfTheSupplyDelta = _params.p2pBorrowAmount > 0
            ? (((_params.p2pSupplyDelta * _params.lastPoolSupplyIndex) / RAY) * RAY) /
                ((_params.p2pSupplyAmount * _params.lastP2PSupplyIndex) / RAY)
            : 0;
        uint256 shareOfTheBorrowDelta = _params.p2pSupplyAmount > 0
            ? (((_params.p2pBorrowDelta * _params.lastPoolBorrowIndex) / RAY) * RAY) /
                ((_params.p2pBorrowAmount * _params.lastP2PBorrowIndex) / RAY)
            : 0;
        p2pSupplyIndex_ =
            _params.lastP2PSupplyIndex *
                ((RAY - shareOfTheSupplyDelta) * (p2pIncrease - (_params.reserveFactor * (p2pIncrease - poolSupplyGrowthFactor) / MAX_BASIS_POINTS)) / RAY +
                (shareOfTheSupplyDelta * poolSupplyGrowthFactor) / RAY) /
            RAY;
        p2pBorrowIndex_ =
            _params.lastP2PBorrowIndex *
                ((RAY - shareOfTheBorrowDelta) * (p2pIncrease + (_params.reserveFactor * (poolBorrowGrowthFactor - p2pIncrease) / MAX_BASIS_POINTS)) / RAY +
                (shareOfTheBorrowDelta * poolBorrowGrowthFactor) / RAY) /
            RAY;
    }

    function testIndexComputation() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            0,
            0,
            0,
            0
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            0,
            0,
            0,
            0
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            4 * RAY,
            6 * RAY,
            1 * RAY,
            1 * RAY
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDeltaAndReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            4 * RAY,
            6 * RAY,
            1 * RAY,
            1 * RAY
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }
}
