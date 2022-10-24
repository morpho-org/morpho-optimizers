// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/aave-v2/InterestRatesManager.sol";
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
        uint256 p2pGrowthFactor = (poolSupplyGrowthFactor.percentMul(PercentageMath.PERCENTAGE_FACTOR - _params.p2pIndexCursor) + poolBorrowGrowthFactor.percentMul(_params.p2pIndexCursor));
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

    function testFuzzInterestRates(
        uint64 _p2pSupplyIndex,
        uint64 _p2pBorrowIndex,
        uint64 _poolSupplyIndex,
        uint64 _poolBorrowIndex,
        uint64 _lastPoolSupplyIndex,
        uint64 _lastPoolBorrowIndex,
        uint16 _reserveFactor,
        uint16 _p2pIndexCursor,
        uint64 _p2pSupplyDelta,
        uint64 _p2pBorrowDelta,
        uint64 _p2pSupplyAmount,
        uint64 _p2pBorrowAmount
    ) public {
        hevm.assume(
            (_p2pSupplyAmount * _p2pSupplyIndex) / RAY > (_p2pSupplyDelta * _poolSupplyIndex) / RAY
        );
        hevm.assume(
            (_p2pBorrowAmount * _p2pBorrowIndex) / RAY > (_p2pBorrowDelta * _poolBorrowIndex) / RAY
        );

        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            RAY + uint256(_p2pSupplyIndex), //      p2pSupplyIndex
            RAY + uint256(_p2pBorrowIndex), //      p2pBorrowIndex
            RAY + uint256(_poolSupplyIndex), //     poolSupplyIndex
            RAY + uint256(_poolBorrowIndex), //     poolBorrowIndex
            RAY + uint256(_lastPoolSupplyIndex), // lastPoolSupplyIndex
            RAY + uint256(_lastPoolBorrowIndex), // lastPoolBorrowIndex
            uint256(_reserveFactor) % 10_000, //    reserveFactor
            uint256(_p2pIndexCursor) % 10_000, //   p2pIndexCursor
            Types.Delta(_p2pSupplyDelta, _p2pBorrowDelta, _p2pSupplyAmount, _p2pBorrowAmount)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params);

        assertLe(
            (newP2PSupplyIndex * RAY) / params.lastP2PSupplyIndex - 10,
            (newP2PBorrowIndex * RAY) / params.lastP2PBorrowIndex
        );
    }
}
