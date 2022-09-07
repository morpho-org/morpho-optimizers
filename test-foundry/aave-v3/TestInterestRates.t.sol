// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "@contracts/aave-v3/InterestRatesManager.sol";
import "@forge-std/Test.sol";

contract TestInterestRates is InterestRatesManager, Test {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

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
        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.rayDiv(_params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.rayDiv(_params.lastPoolBorrowIndex);
        uint256 p2pGrowthFactor = (poolSupplyGrowthFactor.percentMul(MAX_BASIS_POINTS - _params.p2pIndexCursor) + poolBorrowGrowthFactor.percentMul(_params.p2pIndexCursor));
        uint256 shareOfTheSupplyDelta = _params.delta.p2pBorrowAmount > 0
            ? (_params.delta.p2pSupplyDelta.wadToRay().rayMul(_params.lastPoolSupplyIndex)).rayDiv(
                _params.delta.p2pSupplyAmount.wadToRay().rayMul(_params.lastP2PSupplyIndex))
            : 0;
        uint256 shareOfTheBorrowDelta = _params.delta.p2pSupplyAmount > 0
            ? (_params.delta.p2pBorrowDelta.wadToRay().rayMul(_params.lastPoolBorrowIndex)).rayDiv(
                _params.delta.p2pBorrowAmount.wadToRay().rayMul(_params.lastP2PBorrowIndex))
            : 0;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pSupplyGrowthFactor = p2pGrowthFactor - _params.reserveFactor.percentMul(p2pGrowthFactor - poolSupplyGrowthFactor);
            uint256 p2pBorrowGrowthFactor = p2pGrowthFactor + _params.reserveFactor.percentMul(poolBorrowGrowthFactor - p2pGrowthFactor);
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex.rayMul(
                    (RAY - shareOfTheSupplyDelta).rayMul(p2pSupplyGrowthFactor) +
                    shareOfTheSupplyDelta.rayMul(poolSupplyGrowthFactor)
                );
            p2pBorrowIndex_ =
                _params.lastP2PBorrowIndex.rayMul(
                    (RAY - shareOfTheBorrowDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheBorrowDelta.rayMul(poolBorrowGrowthFactor)
                );
        } else {
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex.rayMul(
                    (RAY - shareOfTheSupplyDelta).rayMul(poolBorrowGrowthFactor) + 
                    shareOfTheSupplyDelta.rayMul(poolSupplyGrowthFactor)
                );
            p2pBorrowIndex_ = 
                _params.lastP2PBorrowIndex.rayMul(poolBorrowGrowthFactor); 
        }
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
            Types.Delta(0, 0, 0, 0)
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
    }

    function testIndexComputationEdgeCase() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolBorrowIndexTest,
            poolSupplyIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectednewP2PSupplyIndex, uint256 expectednewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 1);
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
        assertApproxEqAbs(newP2PSupplyIndex, expectednewP2PSupplyIndex, 400);
        assertApproxEqAbs(newP2PBorrowIndex, expectednewP2PBorrowIndex, 400);
    }
}
