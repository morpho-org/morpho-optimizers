// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRatesV1.sol";
import "./positions-manager-parts/PositionsManagerForAaveStorage.sol";

import "./libraries/Math.sol";
import "./libraries/Types.sol";

contract InterestRatesV1 is IInterestRatesV1 {
    using Math for uint256;

    /// STRUCT ///

    struct Vars {
        uint256 shareOfTheDelta; // Share of delta in the total P2P amount.
        uint256 supplyP2PGrowthFactor; // Supply growth factor (between now and the last update).
        uint256 borrowP2PGrowthFactor; // Borrow growth factor (between now and the last update).
        uint256 supplyPoolGrowthFactor; // Borrow growth factor (between now and the last update).
        uint256 borrowPoolGrowthFactor; // Borrow growth factor (between now and the last update).
    }

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    mapping(address => uint256) public supplyWeight; // supply rate weigth in the weigthed mean.
    mapping(address => uint256) public borrowWeight; // borrow rate weigth in the weigthed mean.

    /// PUBLIC ///

    function createMarket(address _marketAddress) public {
        supplyWeight[_marketAddress] = 1;
        borrowWeight[_marketAddress] = 1;
    }

    function setWeights(
        address _marketAddress,
        uint256 _supplyWeigth,
        uint256 _borrowWeigth
    ) public {
        supplyWeight[_marketAddress] = _supplyWeigth;
        borrowWeight[_marketAddress] = _borrowWeigth;
    }

    /// EXTERNAL ///

    /// @notice Computes and return new P2P exchange rates.
    /// @param _params Parameters:
    ///             supplyP2pExchangeRate The current supply P2P exchange rate.
    ///             borrowP2pExchangeRate The current borrow P2P exchange rate.
    ///             poolSupplyExchangeRate The current pool supply exchange rate.
    ///             poolBorrowExchangeRate The current pool borrow exchange rate.
    ///             lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    ///             lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    ///             reserveFactor The reserve factor percentage (10 000 = 100%).
    ///             delta The deltas and P2P amounts.
    /// @return newSupplyP2PExchangeRate The updated supplyP2PExchangeRate.
    /// @return newBorrowP2PExchangeRate The updated borrowP2PExchangeRate.
    function computeP2PExchangeRates(Types.Params memory _params)
        public
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        Vars memory vars;
        (
            vars.supplyP2PGrowthFactor,
            vars.borrowP2PGrowthFactor,
            vars.supplyPoolGrowthFactor,
            vars.borrowPoolGrowthFactor
        ) = _computeGrowthFactors(
            _params.poolTokenAddress,
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        if (_params.delta.supplyP2PAmount == 0 || _params.delta.supplyP2PDelta == 0) {
            newSupplyP2PExchangeRate = _params.supplyP2pExchangeRate.rayMul(
                vars.supplyP2PGrowthFactor
            );
        } else {
            vars.shareOfTheDelta = Math.min(
                _params
                .delta
                .supplyP2PDelta
                .wadToRay()
                .rayMul(_params.poolSupplyExchangeRate)
                .rayDiv(_params.supplyP2pExchangeRate)
                .rayDiv(_params.delta.supplyP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newSupplyP2PExchangeRate = _params.supplyP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.supplyP2PGrowthFactor) +
                    vars.shareOfTheDelta.rayMul(vars.supplyPoolGrowthFactor)
            );
        }

        if (_params.delta.borrowP2PAmount == 0 || _params.delta.borrowP2PDelta == 0) {
            newBorrowP2PExchangeRate = _params.borrowP2pExchangeRate.rayMul(
                vars.borrowP2PGrowthFactor
            );
        } else {
            vars.shareOfTheDelta = Math.min(
                _params
                .delta
                .borrowP2PDelta
                .wadToRay()
                .rayMul(_params.poolBorrowExchangeRate)
                .rayDiv(_params.borrowP2pExchangeRate)
                .rayDiv(_params.delta.borrowP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newBorrowP2PExchangeRate = _params.borrowP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.borrowP2PGrowthFactor) +
                    vars.shareOfTheDelta.rayMul(vars.borrowPoolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns supply P2P growthfactor and borrow P2P growthfactor.
    /// @param _poolSupplyExchangeRate The current pool supply exchange rate.
    /// @param _poolBorrowExchangeRate The current pool borrow exchange rate.
    /// @param _lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    /// @param _lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return supplyP2PGrowthFactor The supply P2P growthfactor.
    /// @return borrowP2PGrowthFactor The borrow P2P growthfactor.
    /// @return supplyPoolGrowthFactor The supply pool growthfactor.
    /// @return borrowPoolGrowthFactor The borrow pool growthfactor.
    function _computeGrowthFactors(
        address _poolTokenAddress,
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate,
        uint256 _reserveFactor
    )
        internal
        view
        returns (
            uint256 supplyP2PGrowthFactor,
            uint256 borrowP2PGrowthFactor,
            uint256 supplyPoolGrowthFactor,
            uint256 borrowPoolGrowthFactor
        )
    {
        supplyPoolGrowthFactor = _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate);
        borrowPoolGrowthFactor = _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate);

        uint256 memorySupplyWeight = supplyWeight[_poolTokenAddress];
        uint256 memoryBorrowWeight = borrowWeight[_poolTokenAddress];
        uint256 WeightsSum = memorySupplyWeight + memoryBorrowWeight;

        uint256 memoryVariable = ((MAX_BASIS_POINTS - _reserveFactor) *
            (memorySupplyWeight *
                supplyPoolGrowthFactor +
                memoryBorrowWeight *
                borrowPoolGrowthFactor)) /
            WeightsSum /
            MAX_BASIS_POINTS;

        supplyP2PGrowthFactor =
            memoryVariable -
            (_reserveFactor * supplyPoolGrowthFactor) /
            MAX_BASIS_POINTS;

        borrowP2PGrowthFactor =
            memoryVariable +
            (_reserveFactor * borrowPoolGrowthFactor) /
            MAX_BASIS_POINTS;
    }
}
