// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    uint256 public supplyP2PIndex = 1 * WAD;
    uint256 public borrowP2PIndex = 1 * WAD;
    uint256 public poolSupplyIndex = 2 * WAD;
    uint256 public poolBorrowIndex = 3 * WAD;
    uint256 public lastPoolSupplyIndex = 1 * WAD;
    uint256 public lastPoolBorrowIndex = 1 * WAD;
    uint256 public reserveFactor0PerCent = 0;
    uint256 public reserveFactor50PerCent = 5_000;
    uint256 public supplyWeigth = 2;
    uint256 public borrowWeigth = 1;

    function computeP2PIndexes(Types.Params memory params)
        public
        view
        returns (uint256 supplyP2PIndex_, uint256 borrowP2PIndex_)
    {
        uint256 supplyPoolIncrease = (params.poolSupplyIndex * WAD / params.lastPoolSupplyIndex); // prettier-ignore
        uint256 borrowPoolIncrease  = (params.poolBorrowIndex * WAD / params.lastPoolBorrowIndex); // prettier-ignore
        uint256 p2pIncrease = ((supplyWeigth * supplyPoolIncrease + borrowWeigth * borrowPoolIncrease) / (supplyWeigth + borrowWeigth)); // prettier-ignore
        uint256 shareOfTheSupplyDelta = params.delta.supplyP2PAmount > 0 
            ? (params.delta.supplyP2PDelta * params.poolSupplyIndex / WAD) * WAD 
                / (params.delta.supplyP2PAmount * params.supplyP2PIndex / WAD) 
            : 0; // prettier-ignore
        uint256 shareOfTheBorrowDelta = params.delta.borrowP2PAmount > 0 
            ? (params.delta.borrowP2PDelta * params.poolBorrowIndex / WAD) * WAD 
                / (params.delta.borrowP2PAmount * params.borrowP2PIndex / WAD) 
            : 0; // prettier-ignore
        supplyP2PIndex_ = params.supplyP2PIndex * 
            (
                (WAD - shareOfTheSupplyDelta) * 
                    ((MAX_BASIS_POINTS - params.reserveFactor) * p2pIncrease + params.reserveFactor * supplyPoolIncrease) / MAX_BASIS_POINTS / WAD + 
                shareOfTheSupplyDelta * 
                    supplyPoolIncrease / WAD
            ) / WAD; // prettier-ignore
        borrowP2PIndex_ = params.borrowP2PIndex * 
            (
                (WAD - shareOfTheBorrowDelta) * 
                    ((MAX_BASIS_POINTS - params.reserveFactor) * p2pIncrease + params.reserveFactor * borrowPoolIncrease) / MAX_BASIS_POINTS / WAD + 
                shareOfTheBorrowDelta * 
                    borrowPoolIncrease / WAD
            ) / WAD; // prettier-ignore
    }

    function testIndexComputation() public {
        Types.Params memory params = Types.Params(
            supplyP2PIndex,
            borrowP2PIndex,
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            reserveFactor0PerCent,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = interestRates.computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PIndex, uint256 expectedNewBorrowP2PIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newSupplyP2PIndex, expectedNewSupplyP2PIndex, 1);
        assertApproxEq(newBorrowP2PIndex, expectedNewBorrowP2PIndex, 1);
    }

    function testIndexComputationWithReserveFactor() public {
        Types.Params memory params = Types.Params(
            supplyP2PIndex,
            borrowP2PIndex,
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            reserveFactor50PerCent,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = interestRates.computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PIndex, uint256 expectedNewBorrowP2PIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newSupplyP2PIndex, expectedNewSupplyP2PIndex, 1);
        assertApproxEq(newBorrowP2PIndex, expectedNewBorrowP2PIndex, 1);
    }

    function testIndexComputationWithDelta() public {
        Types.Params memory params = Types.Params(
            supplyP2PIndex,
            borrowP2PIndex,
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            reserveFactor0PerCent,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = interestRates.computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PIndex, uint256 expectedNewBorrowP2PIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newSupplyP2PIndex, expectedNewSupplyP2PIndex, 1);
        assertApproxEq(newBorrowP2PIndex, expectedNewBorrowP2PIndex, 1);
    }

    function testIndexComputationWithDeltaAndReserveFactor() public {
        Types.Params memory params = Types.Params(
            supplyP2PIndex,
            borrowP2PIndex,
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            reserveFactor50PerCent,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = interestRates.computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PIndex, uint256 expectedNewBorrowP2PIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newSupplyP2PIndex, expectedNewSupplyP2PIndex, 1);
        assertApproxEq(newBorrowP2PIndex, expectedNewBorrowP2PIndex, 1);
    }

    function testFuzzInterestRates(
        uint64 _1,
        uint64 _2,
        uint64 _3,
        uint64 _4,
        uint64 _5,
        uint64 _6,
        uint16 _7,
        uint64 _8,
        uint64 _9,
        uint64 _10,
        uint64 _11
    ) public {
        uint256 _supplyP2PIndex = WAD + _1;
        uint256 _borrowP2PIndex = WAD + _2;
        uint256 _poolSupplyIndex = WAD + _3;
        uint256 _poolBorrowIndex = WAD + _4;
        uint256 _lastPoolSupplyIndex = WAD + _5;
        uint256 _lastPoolBorrowIndex = WAD + _6;
        uint256 _reserveFactor = _7 % 10_000;
        uint256 _supplyP2PDelta = WAD + _8;
        uint256 _borrowP2PDelta = WAD + _9;
        uint256 _supplyP2PAmount = WAD + _10;
        uint256 _borrowP2PAmount = WAD + _11;

        hevm.assume(_lastPoolSupplyIndex <= _poolSupplyIndex); // prettier-ignore
        hevm.assume(_lastPoolBorrowIndex <= _poolBorrowIndex); // prettier-ignore
        hevm.assume(_poolBorrowIndex * WAD / _lastPoolBorrowIndex > _poolSupplyIndex * WAD / _lastPoolSupplyIndex); // prettier-ignore
        hevm.assume(_supplyP2PAmount * _supplyP2PIndex / WAD > _supplyP2PDelta * _poolSupplyIndex / WAD); // prettier-ignore
        hevm.assume(_borrowP2PAmount * _borrowP2PIndex / WAD > _borrowP2PDelta * _poolBorrowIndex / WAD); // prettier-ignore

        Types.Params memory params = Types.Params(
            _supplyP2PIndex,
            _borrowP2PIndex,
            _poolSupplyIndex,
            _poolBorrowIndex,
            _lastPoolSupplyIndex,
            _lastPoolBorrowIndex,
            _reserveFactor,
            Types.Delta(_supplyP2PDelta, _borrowP2PDelta, _supplyP2PAmount, _borrowP2PAmount)
        );

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = interestRates.computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PIndex, uint256 expectedNewBorrowP2PIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newSupplyP2PIndex, expectedNewSupplyP2PIndex, 300); // prettier-ignore
        assertApproxEq(newBorrowP2PIndex, expectedNewBorrowP2PIndex, 300); // prettier-ignore
    }
}
