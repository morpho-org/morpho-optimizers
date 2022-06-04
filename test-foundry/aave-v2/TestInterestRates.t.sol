// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v2/InterestRatesManager.sol";
import "ds-test/test.sol";
import "forge-std/stdlib.sol";

contract TestInterestRates is InterestRatesManager, DSTest {
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
        uint256 shareOfTheSupplyDelta = _params.delta.p2pBorrowAmount > 0
            ? (((_params.delta.p2pSupplyDelta * _params.lastPoolSupplyIndex) / RAY) * RAY) /
                ((_params.delta.p2pSupplyAmount * _params.lastP2PSupplyIndex) / RAY)
            : 0;
        uint256 shareOfTheBorrowDelta = _params.delta.p2pSupplyAmount > 0
            ? (((_params.delta.p2pBorrowDelta * _params.lastPoolBorrowIndex) / RAY) * RAY) /
                ((_params.delta.p2pBorrowAmount * _params.lastP2PBorrowIndex) / RAY)
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
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
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
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }

    // prettier-ignore
    function testFuzzInterestRates(
        uint64 _1,
        uint64 _2,
        uint64 _3,
        uint64 _4,
        uint64 _5,
        uint64 _6,
        uint16 _7,
        uint16 _8,
        uint64 _9,
        uint64 _10,
        uint64 _11,
        uint64 _12
    ) public {
        uint256 _p2pSupplyIndex = RAY + _1;
        uint256 _p2pBorrowIndex = RAY + _2;
        uint256 _poolSupplyIndex = RAY + _3;
        uint256 _poolBorrowIndex = RAY + _4;
        uint256 _lastPoolSupplyIndex = RAY + _5;
        uint256 _lastPoolBorrowIndex = RAY + _6;
        uint256 _reserveFactor = _7 % 10_000;
        uint256 _p2pIndexCursor = _8 % 10_000;
        uint256 _p2pSupplyDelta = RAY + _9;
        uint256 _p2pBorrowDelta = RAY + _10;
        uint256 _p2pSupplyAmount = RAY + _11;
        uint256 _p2pBorrowAmount = RAY + _12;

        hevm.assume(_lastPoolSupplyIndex <= _poolSupplyIndex);
        hevm.assume(_lastPoolBorrowIndex <= _poolBorrowIndex);
        hevm.assume(_poolBorrowIndex * RAY / _lastPoolBorrowIndex > _poolSupplyIndex * RAY / _lastPoolSupplyIndex);
        hevm.assume(_p2pSupplyAmount * _p2pSupplyIndex / RAY > _p2pSupplyDelta * _poolSupplyIndex / RAY);
        hevm.assume(_p2pBorrowAmount * _p2pBorrowIndex / RAY > _p2pBorrowDelta * _poolBorrowIndex / RAY);

        InterestRatesManager.Params memory params = InterestRatesManager.Params(_p2pSupplyIndex, _p2pBorrowIndex, _poolSupplyIndex, _poolBorrowIndex, _lastPoolSupplyIndex, _lastPoolBorrowIndex, _reserveFactor, _p2pIndexCursor, Types.Delta(_p2pSupplyDelta, _p2pBorrowDelta, _p2pSupplyAmount, _p2pBorrowAmount));

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params);
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params);
        assertApproxEq(newP2PSupplyIndex, expectednewP2PSupplyIndex, 400);
        assertApproxEq(newP2PBorrowIndex, expectednewP2PBorrowIndex, 400);
    }
}
