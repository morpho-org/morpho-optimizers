// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    uint256 public supplyP2PExchangeRate = 1 * WAD;
    uint256 public borrowP2PExchangeRate = 1 * WAD;
    uint256 public poolSupplyExchangeRate = 2 * WAD;
    uint256 public poolBorrowExchangeRate = 3 * WAD;
    uint256 public lastPoolSupplyExchangeRate = 1 * WAD;
    uint256 public lastPoolBorrowExchangeRate = 1 * WAD;
    uint256 public reserveFactor0PerCent = 0;
    uint256 public reserveFactor50PerCent = 5_000;
    uint256 public supplyWeigth = 2;
    uint256 public borrowWeigth = 1;

    function computeP2PExchangeRates(Types.Params memory params)
        public
        view
        returns (uint256 supplyP2PExchangeRate_, uint256 borrowP2PExchangeRate_)
    {
        uint256 supplyPoolIncrease = (params.poolSupplyExchangeRate * WAD / params.lastPoolSupplyExchangeRate); // prettier-ignore
        uint256 borrowPoolIncrease  = (params.poolBorrowExchangeRate * WAD / params.lastPoolBorrowExchangeRate); // prettier-ignore
        uint256 p2pIncrease = ((supplyWeigth * supplyPoolIncrease + borrowWeigth * borrowPoolIncrease) / (supplyWeigth + borrowWeigth)); // prettier-ignore
        uint256 shareOfTheSupplyDelta = params.delta.supplyP2PAmount > 0 
            ? (params.delta.supplyP2PDelta * params.poolSupplyExchangeRate / WAD) * WAD 
                / (params.delta.supplyP2PAmount * params.supplyP2PExchangeRate / WAD) 
            : 0; // prettier-ignore
        uint256 shareOfTheBorrowDelta = params.delta.borrowP2PAmount > 0 
            ? (params.delta.borrowP2PDelta * params.poolBorrowExchangeRate / WAD) * WAD 
                / (params.delta.borrowP2PAmount * params.borrowP2PExchangeRate / WAD) 
            : 0; // prettier-ignore
        supplyP2PExchangeRate_ = params.supplyP2PExchangeRate * 
            (
                (WAD - shareOfTheSupplyDelta) * 
                    ((MAX_BASIS_POINTS - params.reserveFactor) * p2pIncrease + params.reserveFactor * supplyPoolIncrease) / MAX_BASIS_POINTS / WAD + 
                shareOfTheSupplyDelta * 
                    supplyPoolIncrease / WAD
            ) / WAD; // prettier-ignore
        borrowP2PExchangeRate_ = params.borrowP2PExchangeRate * 
            (
                (WAD - shareOfTheBorrowDelta) * 
                    ((MAX_BASIS_POINTS - params.reserveFactor) * p2pIncrease + params.reserveFactor * borrowPoolIncrease) / MAX_BASIS_POINTS / WAD + 
                shareOfTheBorrowDelta * 
                    borrowPoolIncrease / WAD
            ) / WAD; // prettier-ignore
    }

    function testExchangeRateComputation() public {
        Types.Params memory params = Types.Params(
            supplyP2PExchangeRate,
            borrowP2PExchangeRate,
            poolSupplyExchangeRate,
            poolBorrowExchangeRate,
            lastPoolSupplyExchangeRate,
            lastPoolBorrowExchangeRate,
            reserveFactor0PerCent,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates.computeP2PExchangeRates(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PExchangeRate, uint256 expectedNewBorrowP2PExchangeRate) = computeP2PExchangeRates(params); // prettier-ignore
        assertApproxEq(newSupplyP2PExchangeRate, expectedNewSupplyP2PExchangeRate, 1);
        assertApproxEq(newBorrowP2PExchangeRate, expectedNewBorrowP2PExchangeRate, 1);
    }

    function testExchangeRateComputationWithReserveFactor() public {
        Types.Params memory params = Types.Params(
            supplyP2PExchangeRate,
            borrowP2PExchangeRate,
            poolSupplyExchangeRate,
            poolBorrowExchangeRate,
            lastPoolSupplyExchangeRate,
            lastPoolBorrowExchangeRate,
            reserveFactor50PerCent,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates.computeP2PExchangeRates(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PExchangeRate, uint256 expectedNewBorrowP2PExchangeRate) = computeP2PExchangeRates(params); // prettier-ignore
        assertApproxEq(newSupplyP2PExchangeRate, expectedNewSupplyP2PExchangeRate, 1);
        assertApproxEq(newBorrowP2PExchangeRate, expectedNewBorrowP2PExchangeRate, 1);
    }

    function testExchangeRateComputationWithDelta() public {
        Types.Params memory params = Types.Params(
            supplyP2PExchangeRate,
            borrowP2PExchangeRate,
            poolSupplyExchangeRate,
            poolBorrowExchangeRate,
            lastPoolSupplyExchangeRate,
            lastPoolBorrowExchangeRate,
            reserveFactor0PerCent,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates.computeP2PExchangeRates(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PExchangeRate, uint256 expectedNewBorrowP2PExchangeRate) = computeP2PExchangeRates(params); // prettier-ignore
        assertApproxEq(newSupplyP2PExchangeRate, expectedNewSupplyP2PExchangeRate, 1);
        assertApproxEq(newBorrowP2PExchangeRate, expectedNewBorrowP2PExchangeRate, 1);
    }

    function testExchangeRateComputationWithDeltaAndReserveFactor() public {
        Types.Params memory params = Types.Params(
            supplyP2PExchangeRate,
            borrowP2PExchangeRate,
            poolSupplyExchangeRate,
            poolBorrowExchangeRate,
            lastPoolSupplyExchangeRate,
            lastPoolBorrowExchangeRate,
            reserveFactor50PerCent,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates.computeP2PExchangeRates(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PExchangeRate, uint256 expectedNewBorrowP2PExchangeRate) = computeP2PExchangeRates(params); // prettier-ignore
        assertApproxEq(newSupplyP2PExchangeRate, expectedNewSupplyP2PExchangeRate, 1);
        assertApproxEq(newBorrowP2PExchangeRate, expectedNewBorrowP2PExchangeRate, 1);
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
        uint256 _supplyP2PExchangeRate = WAD + _1;
        uint256 _borrowP2PExchangeRate = WAD + _2;
        uint256 _poolSupplyExchangeRate = WAD + _3;
        uint256 _poolBorrowExchangeRate = WAD + _4;
        uint256 _lastPoolSupplyExchangeRate = WAD + _5;
        uint256 _lastPoolBorrowExchangeRate = WAD + _6;
        uint256 _reserveFactor = _7 % 10_000;
        uint256 _supplyP2PDelta = WAD + _8;
        uint256 _borrowP2PDelta = WAD + _9;
        uint256 _supplyP2PAmount = WAD + _10;
        uint256 _borrowP2PAmount = WAD + _11;

        hevm.assume(_lastPoolSupplyExchangeRate <= _poolSupplyExchangeRate); // prettier-ignore
        hevm.assume(_lastPoolBorrowExchangeRate <= _poolBorrowExchangeRate); // prettier-ignore
        hevm.assume(_poolBorrowExchangeRate * WAD / _lastPoolBorrowExchangeRate > _poolSupplyExchangeRate * WAD / _lastPoolSupplyExchangeRate); // prettier-ignore
        hevm.assume(_supplyP2PAmount * _supplyP2PExchangeRate / WAD > _supplyP2PDelta * _poolSupplyExchangeRate / WAD); // prettier-ignore
        hevm.assume(_borrowP2PAmount * _borrowP2PExchangeRate / WAD > _borrowP2PDelta * _poolBorrowExchangeRate / WAD); // prettier-ignore

        Types.Params memory params = Types.Params(
            _supplyP2PExchangeRate,
            _borrowP2PExchangeRate,
            _poolSupplyExchangeRate,
            _poolBorrowExchangeRate,
            _lastPoolSupplyExchangeRate,
            _lastPoolBorrowExchangeRate,
            _reserveFactor,
            Types.Delta(_supplyP2PDelta, _borrowP2PDelta, _supplyP2PAmount, _borrowP2PAmount)
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates.computeP2PExchangeRates(params); // prettier-ignore
        (uint256 expectedNewSupplyP2PExchangeRate, uint256 expectedNewBorrowP2PExchangeRate) = computeP2PExchangeRates(params); // prettier-ignore
        assertApproxEq(newSupplyP2PExchangeRate, expectedNewSupplyP2PExchangeRate, 300); // prettier-ignore
        assertApproxEq(newBorrowP2PExchangeRate, expectedNewBorrowP2PExchangeRate, 300); // prettier-ignore
    }
}
